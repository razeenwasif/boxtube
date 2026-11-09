import Foundation

public enum BoxtubeError: LocalizedError, Sendable {
    case missingAPIKey
    case http(Int, String)
    case decoding(String)
    case notSignedIn(String)
    /// A YouTube API refusal with its machine-readable reason (e.g. quotaExceeded, subscriptionDuplicate).
    case youtube(status: Int, reason: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add a YouTube Data API key to search and load durations."
        case .http(let code, let message): "YouTube returned \(code): \(message)"
        case .decoding(let what): "Couldn't read \(what)."
        case .notSignedIn(let message): message
        case .youtube(_, let reason, let message): reason == "quotaExceeded" ? "Today's YouTube quota is used up. It resets at midnight Pacific time." : message
        }
    }
}

/// YouTube Data API v3. Every call is cheap except `search` (100 units), which only runs when the user types.
public actor YouTubeClient {
    private let apiKey: String?
    private let session: URLSession
    private let base = URL(string: "https://www.googleapis.com/youtube/v3/")!

    public nonisolated let hasKey: Bool

    public init(apiKey: String?, session: URLSession = .shared) {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = (trimmed?.isEmpty == false && trimmed != "paste-your-key-here" && trimmed?.hasPrefix("$(") == false) ? trimmed : nil
        self.apiKey = usable
        self.hasKey = usable != nil
        self.session = session
    }

    // MARK: Endpoints

    public func videos(ids: [String], token: String? = nil) async throws -> [Video] {
        var result: [Video] = []
        for chunk in ids.uniqued().chunked(50) {
            let page: Page<VideoResource> = try await get("videos", [
                "part": "snippet,contentDetails,statistics,liveStreamingDetails",
                "id": chunk.joined(separator: ","),
                "maxResults": "50",
            ], token: token)
            result += page.items.map(\.video)
        }
        return result
    }

    public func popular(categoryId: String? = nil, regionCode: String = Locale.current.region?.identifier ?? "US") async throws -> [Video] {
        var query = ["part": "snippet,contentDetails,statistics", "chart": "mostPopular", "maxResults": "40", "regionCode": regionCode]
        if let categoryId { query["videoCategoryId"] = categoryId }
        let page: Page<VideoResource> = try await get("videos", query)
        return page.items.map(\.video)
    }

    public func search(_ text: String, duration: String? = nil) async throws -> [Video] {
        var query = ["part": "snippet", "q": text, "type": "video", "maxResults": "25", "safeSearch": "moderate"]
        if let duration { query["videoDuration"] = duration }
        let page: Page<SearchResource> = try await get("search", query, cost: 100)
        let ids = page.items.compactMap(\.id.videoId)
        let details = try await videos(ids: ids)
        let byId = Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })
        return ids.compactMap { byId[$0] }
    }

    public func searchChannels(_ text: String) async throws -> [Channel] {
        let page: Page<SearchResource> = try await get("search", ["part": "snippet", "q": text, "type": "channel", "maxResults": "10"], cost: 100)
        let ids = page.items.compactMap(\.id.channelId)
        return try await channels(ids: ids)
    }

    public func channels(ids: [String]) async throws -> [Channel] {
        var result: [Channel] = []
        for chunk in ids.uniqued().chunked(50) {
            let page: Page<ChannelResource> = try await get("channels", ["part": "snippet,statistics", "id": chunk.joined(separator: ",")])
            result += page.items.map(\.channel)
        }
        return result
    }

    public struct TopComment: Sendable, Hashable {
        public var author: String
        public var text: String
        public var likes: Int
        public var total: Int?
    }

    /// The most relevant comment plus the video's comment count (2 units).
    public func topComment(videoId: String) async throws -> TopComment? {
        let page: Page<CommentThreadResource> = try await get("commentThreads", ["part": "snippet", "videoId": videoId, "order": "relevance", "maxResults": "1", "textFormat": "plainText"])
        guard let c = page.items.first?.snippet.topLevelComment.snippet else { return nil }
        let stats: Page<VideoStatsOnly> = try await get("videos", ["part": "statistics", "id": videoId])
        return TopComment(author: c.authorDisplayName, text: c.textDisplay, likes: c.likeCount ?? 0, total: stats.items.first?.statistics.commentCount.flatMap(Int.init))
    }

    /// Shorts uploaded by a channel live in the hidden `UUSH…` playlist.
    public func shortsIds(channelId: String) async throws -> [String] {
        guard channelId.hasPrefix("UC") else { return [] }
        let playlist = "UUSH" + channelId.dropFirst(2)
        let page: Page<PlaylistItemResource> = try await get("playlistItems", ["part": "contentDetails", "playlistId": String(playlist), "maxResults": "15"])
        return page.items.map(\.contentDetails.videoId)
    }

    // MARK: Your account (OAuth, read-only)

    public struct AccountPlaylist: Sendable, Hashable {
        public var id: String
        public var title: String
        public var isPrivate: Bool
    }

    /// Channels you subscribe to on YouTube (1 unit per 50).
    public func mySubscriptions(token: String) async throws -> [Channel] {
        let items: [SubscriptionResource] = try await all("subscriptions", ["part": "snippet", "mine": "true", "order": "alphabetical"], token: token, limit: 1000)
        return items.map { Channel(id: $0.snippet.resourceId.channelId ?? "", title: $0.snippet.title, avatarURL: $0.snippet.thumbnails.avatar) }
            .filter { !$0.id.isEmpty }
    }

    /// Playlists you own (1 unit per 50).
    public func myPlaylists(token: String) async throws -> [AccountPlaylist] {
        let items: [PlaylistResource] = try await all("playlists", ["part": "snippet,status", "mine": "true"], token: token, limit: 200)
        return items.map { AccountPlaylist(id: $0.id, title: $0.snippet.title, isPrivate: $0.status?.privacyStatus != "public") }
    }

    /// Video ids in a playlist, in order (1 unit per 50).
    public func playlistVideoIds(_ playlistId: String, token: String, limit: Int = 200) async throws -> [String] {
        let items: [PlaylistItemResource] = try await all("playlistItems", ["part": "contentDetails", "playlistId": playlistId], token: token, limit: limit)
        return items.map(\.contentDetails.videoId)
    }

    /// Videos you've liked, newest first (1 unit per 50).
    public func myLikedVideos(token: String, limit: Int = 200) async throws -> [Video] {
        let items: [VideoResource] = try await all("videos", ["part": "snippet,contentDetails,statistics", "myRating": "like"], token: token, limit: limit)
        return items.map(\.video)
    }

    private func all<Item: Decodable>(_ path: String, _ query: [String: String], token: String, limit: Int) async throws -> [Item] {
        var items: [Item] = []
        var pageToken: String?
        repeat {
            var q = query
            q["maxResults"] = "50"
            if let pageToken { q["pageToken"] = pageToken }
            let page: Page<Item> = try await get(path, q, token: token)
            items += page.items
            pageToken = page.nextPageToken
        } while pageToken != nil && items.count < limit
        return Array(items.prefix(limit))
    }

    // MARK: Transport

    // MARK: Quota

    /// Estimated quota units spent since the last call (1 per list call, 100 per search, 50 per change).
    private var unitsSpent = 0
    public func takeUnitsSpent() -> Int { defer { unitsSpent = 0 }; return unitsSpent }

    // MARK: Changes to your account (OAuth, youtube.force-ssl)

    /// Like, dislike or clear ("none") your rating of a video.
    public func rate(videoId: String, rating: String, token: String) async throws {
        _ = try await send("POST", "videos/rate", ["id": videoId, "rating": rating], token: token)
    }

    public func subscribe(channelId: String, token: String) async throws {
        let body = ["snippet": ["resourceId": ["kind": "youtube#channel", "channelId": channelId]]]
        _ = try await send("POST", "subscriptions", ["part": "snippet"], body: body, token: token)
    }

    /// Your subscription to a channel, if any (unsubscribing needs its id).
    public func subscriptionId(channelId: String, token: String) async throws -> String? {
        let page: Page<IdOnly> = try await get("subscriptions", ["part": "id", "mine": "true", "forChannelId": channelId], token: token)
        return page.items.first?.id
    }

    public func deleteSubscription(id: String, token: String) async throws {
        _ = try await send("DELETE", "subscriptions", ["id": id], token: token)
    }

    public func addToPlaylist(playlistId: String, videoId: String, token: String) async throws {
        let body = ["snippet": ["playlistId": playlistId, "resourceId": ["kind": "youtube#video", "videoId": videoId]]]
        _ = try await send("POST", "playlistItems", ["part": "snippet"], body: body, token: token)
    }

    /// The playlist entries holding a video (removing needs their ids).
    public func playlistItemIds(playlistId: String, videoId: String, token: String) async throws -> [String] {
        let page: Page<IdOnly> = try await get("playlistItems", ["part": "id", "playlistId": playlistId, "videoId": videoId, "maxResults": "50"], token: token)
        return page.items.map(\.id)
    }

    public func deletePlaylistItem(id: String, token: String) async throws {
        _ = try await send("DELETE", "playlistItems", ["id": id], token: token)
    }

    /// Makes a private playlist on your channel and returns its id.
    public func createPlaylist(title: String, token: String) async throws -> String {
        let body = ["snippet": ["title": title], "status": ["privacyStatus": "private"]]
        let data = try await send("POST", "playlists", ["part": "snippet,status"], body: body, token: token)
        guard let made = try? Self.decoder.decode(IdOnly.self, from: data) else { throw BoxtubeError.decoding("new playlist") }
        return made.id
    }

    /// Deletes one of your playlists on YouTube.
    public func deletePlaylist(id: String, token: String) async throws {
        _ = try await send("DELETE", "playlists", ["id": id], token: token)
    }

    private func send(_ method: String, _ path: String, _ query: [String: String], body: [String: Any]? = nil, token: String) async throws -> Data {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        unitsSpent += 50
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.refusal(status, data) }
        return data
    }

    private static func refusal(_ status: Int, _ data: Data) -> BoxtubeError {
        let e = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error
        return .youtube(status: status, reason: e?.errors?.first?.reason ?? "", message: e?.message ?? "request failed")
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String], token: String? = nil, cost: Int = 1) async throws -> T {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        if token == nil {
            guard let apiKey else { throw BoxtubeError.missingAPIKey }
            items.append(URLQueryItem(name: "key", value: apiKey))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        else if let bundle = Bundle.main.bundleIdentifier { request.setValue(bundle, forHTTPHeaderField: "X-Ios-Bundle-Identifier") }
        unitsSpent += cost
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message ?? "request failed"
            throw BoxtubeError.http(status, message)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw BoxtubeError.decoding(path)
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Wire types

private struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable { var reason: String? }
    struct E: Decodable { var message: String; var errors: [Detail]? }
    var error: E
}
private struct IdOnly: Decodable { var id: String }
private struct Page<Item: Decodable>: Decodable { var items: [Item]; var nextPageToken: String? }

private struct Thumbs: Decodable {
    struct T: Decodable { var url: URL }
    var `default`: T?; var medium: T?; var high: T?; var standard: T?; var maxres: T?
    /// Card-sized (640 px) first: full 1280 px images only for hero cards, which ask for them directly.
    var best: URL? { (standard ?? high ?? maxres ?? medium ?? `default`)?.url }
    var avatar: URL? { (high ?? medium ?? `default`)?.url }
}

private struct VideoResource: Decodable {
    struct Snippet: Decodable {
        var channelId: String; var channelTitle: String; var title: String; var description: String
        var publishedAt: Date; var thumbnails: Thumbs; var categoryId: String?; var liveBroadcastContent: String?
    }
    struct Details: Decodable { var duration: String? }
    struct Stats: Decodable { var viewCount: String?; var likeCount: String? }
    var id: String; var snippet: Snippet; var contentDetails: Details?; var statistics: Stats?

    var video: Video {
        let seconds = contentDetails?.duration.flatMap(ISODuration.seconds)
        return Video(
            id: id, channelId: snippet.channelId, channelTitle: snippet.channelTitle, title: snippet.title,
            summary: snippet.description, publishedAt: snippet.publishedAt, durationSeconds: seconds,
            viewCount: statistics?.viewCount.flatMap(Int.init), likeCount: statistics?.likeCount.flatMap(Int.init),
            thumbnailURL: snippet.thumbnails.best, isShort: (seconds ?? 999) <= 60,
            isLive: snippet.liveBroadcastContent == "live", categoryId: snippet.categoryId
        )
    }
}

private struct SearchResource: Decodable {
    struct ID: Decodable { var videoId: String?; var channelId: String? }
    var id: ID
}

private struct ChannelResource: Decodable {
    struct Snippet: Decodable { var title: String; var thumbnails: Thumbs }
    struct Stats: Decodable { var subscriberCount: String? }
    var id: String; var snippet: Snippet; var statistics: Stats?
    var channel: Channel {
        Channel(id: id, title: snippet.title, avatarURL: snippet.thumbnails.avatar,
                subscriberCount: statistics?.subscriberCount.flatMap(Int.init))
    }
}

private struct CommentThreadResource: Decodable {
    struct Snippet: Decodable { var topLevelComment: Top }
    struct Top: Decodable { var snippet: Inner }
    struct Inner: Decodable { var authorDisplayName: String; var textDisplay: String; var likeCount: Int? }
    var snippet: Snippet
}

private struct VideoStatsOnly: Decodable {
    struct Stats: Decodable { var commentCount: String? }
    var statistics: Stats
}

private struct SubscriptionResource: Decodable {
    struct Snippet: Decodable { var title: String; var thumbnails: Thumbs; var resourceId: Resource }
    struct Resource: Decodable { var channelId: String? }
    var snippet: Snippet
}

private struct PlaylistResource: Decodable {
    struct Snippet: Decodable { var title: String }
    struct Status: Decodable { var privacyStatus: String? }
    var id: String; var snippet: Snippet; var status: Status?
}

private struct PlaylistItemResource: Decodable {
    struct Details: Decodable { var videoId: String }
    var contentDetails: Details
}

// MARK: - Helpers

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
