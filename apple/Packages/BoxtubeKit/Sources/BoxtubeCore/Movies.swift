import Foundation
import GRDB

/// A YouTube movie you've bought, rented or saved for later. YouTube's API can't read your purchases,
/// so you add these yourself; they play in the YouTube app, since paid movies don't play in embeds.
public struct Movie: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "movie"

    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case rented, bought, saved
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .rented: "Rented"
            case .bought: "Bought"
            case .saved: "Saved for later"
            }
        }
    }

    public var videoId: String
    public var kind: Kind
    public var addedAt: Date
    /// When a rental began (set when it's filed as Rented).
    public var rentedAt: Date?
    /// When you first pressed play on a rental, which starts YouTube's shorter clock.
    public var startedAt: Date?

    public init(videoId: String, kind: Kind, addedAt: Date = .now, rentedAt: Date? = nil, startedAt: Date? = nil) {
        self.videoId = videoId; self.kind = kind; self.addedAt = addedAt; self.rentedAt = rentedAt; self.startedAt = startedAt
    }
}

public struct MovieRow: Hashable, Identifiable, Sendable {
    public var movie: Movie
    public var video: Video
    public var id: String { video.id }
}

/// How long a rental has left. YouTube's usual terms: 30 days to start watching, then 48 hours to
/// finish once started (some titles and countries differ).
public enum Rental {
    public static let startWindow: TimeInterval = 30 * 86_400
    public static let watchWindow: TimeInterval = 48 * 3600

    public enum State: Equatable, Sendable {
        case notStarted(left: TimeInterval)
        case watching(left: TimeInterval)
        case expired
    }

    public static func state(rentedAt: Date, startedAt: Date?, now: Date = .now) -> State {
        if let startedAt {
            let end = min(startedAt.addingTimeInterval(watchWindow), rentedAt.addingTimeInterval(startWindow + watchWindow))
            let left = end.timeIntervalSince(now)
            return left > 0 ? .watching(left: left) : .expired
        }
        let left = rentedAt.addingTimeInterval(startWindow).timeIntervalSince(now)
        return left > 0 ? .notStarted(left: left) : .expired
    }

    /// "12 days to start", "18 h left", "40 min left", "Expired".
    public static func label(_ state: State) -> String {
        switch state {
        case .notStarted(let left): return "\(span(left)) to start"
        case .watching(let left): return "\(span(left)) left"
        case .expired: return "Expired"
        }
    }

    static func span(_ t: TimeInterval) -> String {
        let hours = Int(t / 3600)
        if hours >= 48 { return "\(hours / 24) days" }
        if hours >= 1 { return "\(hours) h" }
        return "\(max(1, Int(t / 60))) min"
    }
}

public enum YouTubeLink {
    /// The 11-character video id in a YouTube link (watch, youtu.be, embed, shorts, live, movie) or a bare id.
    public static func videoId(from text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.wholeMatch(of: /[A-Za-z0-9_-]{11}/) != nil { return t }
        if let m = t.firstMatch(of: /[?&]v=([A-Za-z0-9_-]{11})/) { return String(m.1) }
        if let m = t.firstMatch(of: /youtu\.be\/([A-Za-z0-9_-]{11})/) { return String(m.1) }
        if let m = t.firstMatch(of: /\/(?:embed|shorts|live|movie|v)\/([A-Za-z0-9_-]{11})/) { return String(m.1) }
        return nil
    }
}

extension Store {
    /// Files a movie (adding its video if needed). Filing it again changes where it's filed.
    public func addMovie(_ video: Video, kind: Movie.Kind, now: Date = .now) async throws {
        try await writer.write { db in
            try Self.upsert(videos: [video], preserveDetails: true, in: db)
            var movie = try Movie.fetchOne(db, key: video.id) ?? Movie(videoId: video.id, kind: kind, addedAt: now)
            Self.file(&movie, as: kind, now: now)
            try movie.save(db)
        }
    }

    public func setMovieKind(_ videoId: String, _ kind: Movie.Kind, now: Date = .now) async throws {
        try await writer.write { db in
            guard var movie = try Movie.fetchOne(db, key: videoId) else { return }
            Self.file(&movie, as: kind, now: now)
            try movie.update(db)
        }
    }

    /// Marks a rental as started (or not yet started, to undo a mistaken press).
    public func setMovieStarted(_ videoId: String, _ started: Bool, now: Date = .now) async throws {
        try await writer.write { db in
            guard var movie = try Movie.fetchOne(db, key: videoId), movie.kind == .rented else { return }
            movie.startedAt = started ? (movie.startedAt ?? now) : nil
            try movie.update(db)
        }
    }

    public func removeMovie(_ videoId: String) async throws {
        try await writer.write { db in _ = try Movie.deleteOne(db, key: videoId) }
    }

    private static func file(_ movie: inout Movie, as kind: Movie.Kind, now: Date) {
        if kind == .rented {
            if movie.kind != .rented || movie.rentedAt == nil { movie.rentedAt = now; movie.startedAt = nil }
        } else {
            movie.rentedAt = nil; movie.startedAt = nil
        }
        movie.kind = kind
    }
}

extension Q {
    /// Your movies, newest first.
    public static func movies(_ db: Database) throws -> [MovieRow] {
        let movies = try Movie.order(Column("addedAt").desc).fetchAll(db)
        return try movies.compactMap { m in try Video.fetchOne(db, key: m.videoId).map { MovieRow(movie: m, video: $0) } }
    }
}
