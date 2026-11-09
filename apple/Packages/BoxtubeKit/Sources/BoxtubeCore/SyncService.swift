import Foundation

/// What sync needs from YouTube. `YouTubeClient` does the real calls; tests use a stand-in.
public protocol YouTubeWriter: Sendable {
    func rate(videoId: String, rating: String, token: String) async throws
    func subscribe(channelId: String, token: String) async throws
    func subscriptionId(channelId: String, token: String) async throws -> String?
    func deleteSubscription(id: String, token: String) async throws
    func addToPlaylist(playlistId: String, videoId: String, token: String) async throws
    func playlistItemIds(playlistId: String, videoId: String, token: String) async throws -> [String]
    func deletePlaylistItem(id: String, token: String) async throws
    func createPlaylist(title: String, token: String) async throws -> String
    func deletePlaylist(id: String, token: String) async throws
}

extension YouTubeClient: YouTubeWriter {}

/// Sends the outbox (changes you made in Boxtube) to your YouTube account, oldest first.
public actor SyncService {
    public let store: Store
    let youtube: any YouTubeWriter

    public init(store: Store, youtube: any YouTubeWriter) {
        self.store = store
        self.youtube = youtube
    }

    public enum Stop: Sendable, Equatable {
        /// Today's quota is spent; try again after midnight Pacific time.
        case quota
        /// The sign-in doesn't allow changes; sign in again with sync.
        case needsPermission
        /// No connection, or YouTube is having trouble; try again later.
        case unreachable
    }

    public struct Report: Sendable, Equatable {
        public var sent = 0
        public var dropped = 0
        public var stoppedBy: Stop?
    }

    /// An op YouTube refuses this many times is set aside instead of blocking the rest.
    public static let maxAttempts = 3

    public func flush(token: String, limit: Int = 200) async -> Report {
        var report = Report()
        // A change YouTube refused waits for the next run instead of being retried straight away.
        var refused: Set<Int64> = []
        for _ in 0..<limit {
            let skip = refused
            guard let op = try? await store.read({ db in try Q.nextOutboxOp(db, skipping: skip) }) else { break }
            do {
                try await perform(op, token: token)
                try? await store.finishOutbox(op.id ?? 0)
                report.sent += 1
            } catch {
                switch Self.classify(error) {
                case .done:
                    try? await store.finishOutbox(op.id ?? 0)
                    report.sent += 1
                case .drop:
                    try? await store.finishOutbox(op.id ?? 0)
                    report.dropped += 1
                case .retryLater(let message):
                    try? await store.failOutbox(op.id ?? 0, error: message)
                    refused.insert(op.id ?? 0)
                case .stop(let why):
                    report.stoppedBy = why
                    return report
                }
            }
        }
        return report
    }

    private func perform(_ op: OutboxOp, token: String) async throws {
        switch op.kind {
        case .like: try await youtube.rate(videoId: op.target, rating: "like", token: token)
        case .dislike: try await youtube.rate(videoId: op.target, rating: "dislike", token: token)
        case .unrate: try await youtube.rate(videoId: op.target, rating: "none", token: token)
        case .subscribe: try await youtube.subscribe(channelId: op.target, token: token)
        case .unsubscribe:
            if let id = try await youtube.subscriptionId(channelId: op.target, token: token) {
                try await youtube.deleteSubscription(id: id, token: token)
            }
        case .playlistAdd:
            guard let playlistId = op.playlistId, !Store.isLocalPlaylist(playlistId) else { return }
            try await youtube.addToPlaylist(playlistId: playlistId, videoId: op.target, token: token)
        case .playlistRemove:
            guard let playlistId = op.playlistId, !Store.isLocalPlaylist(playlistId) else { return }
            for id in try await youtube.playlistItemIds(playlistId: playlistId, videoId: op.target, token: token) {
                try await youtube.deletePlaylistItem(id: id, token: token)
            }
        case .playlistDelete:
            try await youtube.deletePlaylist(id: op.target, token: token)
        case .playlistCreate:
            guard let title = try await store.read({ db in try Playlist.fetchOne(db, key: op.target)?.title }) else { return }
            let remoteId = try await youtube.createPlaylist(title: title, token: token)
            // From now on the playlist is known by YouTube's id, including queued edits to it.
            try await store.rekeyPlaylist(from: op.target, to: remoteId)
        }
    }

    enum Outcome: Equatable { case done, drop, retryLater(String), stop(Stop) }

    /// How to treat a failure, by YouTube's reason code.
    static func classify(_ error: Error) -> Outcome {
        guard let e = error as? BoxtubeError else { return .stop(.unreachable) }
        switch e {
        case .youtube(let status, let reason, let message):
            switch reason {
            case "subscriptionDuplicate", "videoAlreadyInPlaylist": return .done
            case "subscriptionNotFound", "playlistItemNotFound", "videoNotFound", "playlistNotFound", "channelNotFound": return .drop
            case "quotaExceeded", "dailyLimitExceeded", "rateLimitExceeded", "userRateLimitExceeded": return .stop(.quota)
            case "insufficientPermissions", "forbidden", "authError": return .stop(.needsPermission)
            default:
                if status == 401 { return .stop(.needsPermission) }
                if status == 404 { return .drop }
                if status >= 500 { return .stop(.unreachable) }
                return .retryLater(message)
            }
        case .notSignedIn: return .stop(.needsPermission)
        default: return .stop(.unreachable)
        }
    }
}
