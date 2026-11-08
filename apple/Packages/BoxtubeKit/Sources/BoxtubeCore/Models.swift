import Foundation
import GRDB

// MARK: - Video

public struct Video: Codable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "video"

    public var id: String
    public var channelId: String
    public var channelTitle: String
    public var title: String
    public var summary: String
    public var publishedAt: Date
    public var durationSeconds: Int?
    public var viewCount: Int?
    public var likeCount: Int?
    public var thumbnailURL: URL?
    public var isShort: Bool
    public var isLive: Bool
    public var categoryId: String?
    public var fetchedAt: Date

    public init(
        id: String, channelId: String, channelTitle: String, title: String, summary: String = "",
        publishedAt: Date, durationSeconds: Int? = nil, viewCount: Int? = nil, likeCount: Int? = nil,
        thumbnailURL: URL? = nil, isShort: Bool = false, isLive: Bool = false, categoryId: String? = nil,
        fetchedAt: Date = .now
    ) {
        self.id = id; self.channelId = channelId; self.channelTitle = channelTitle; self.title = title
        self.summary = summary; self.publishedAt = publishedAt; self.durationSeconds = durationSeconds
        self.viewCount = viewCount; self.likeCount = likeCount; self.thumbnailURL = thumbnailURL
        self.isShort = isShort; self.isLive = isLive; self.categoryId = categoryId; self.fetchedAt = fetchedAt
    }

    public var isMusic: Bool { categoryId == "10" }
    public var chapters: [Chapter] { ChapterParser.parse(summary, duration: durationSeconds) }
    public var bestThumbnail: URL {
        thumbnailURL ?? URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")!
    }
    public var maxThumbnail: URL { URL(string: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg")! }
    public var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    public var musicURL: URL { URL(string: "https://music.youtube.com/watch?v=\(id)")! }
}

// MARK: - Channel

public struct Channel: Codable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "channel"

    public var id: String
    public var title: String
    public var avatarURL: URL?
    public var subscriberCount: Int?
    public var isSubscribed: Bool
    public var subscribedAt: Date?
    public var isMusic: Bool
    public var lastFetchedAt: Date?
    public var lastSeenAt: Date?

    public init(
        id: String, title: String, avatarURL: URL? = nil, subscriberCount: Int? = nil,
        isSubscribed: Bool = false, subscribedAt: Date? = nil, isMusic: Bool = false,
        lastFetchedAt: Date? = nil, lastSeenAt: Date? = nil
    ) {
        self.id = id; self.title = title; self.avatarURL = avatarURL; self.subscriberCount = subscriberCount
        self.isSubscribed = isSubscribed; self.subscribedAt = subscribedAt; self.isMusic = isMusic
        self.lastFetchedAt = lastFetchedAt; self.lastSeenAt = lastSeenAt
    }

    public var initials: String {
        let words = title.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

// MARK: - Library

public struct Playlist: Codable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "playlist"

    public var id: String
    public var title: String
    public var isMusic: Bool
    public var isPrivate: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// True once you've set "Show in Music" yourself, so imports stop guessing.
    public var musicChosen: Bool

    public init(id: String = UUID().uuidString, title: String, isMusic: Bool = false, isPrivate: Bool = true,
                createdAt: Date = .now, updatedAt: Date = .now, musicChosen: Bool = false) {
        self.id = id; self.title = title; self.isMusic = isMusic; self.isPrivate = isPrivate
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.musicChosen = musicChosen
    }
}

public struct PlaylistItem: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "playlistItem"
    public var playlistId: String
    public var videoId: String
    public var position: Int
    public var addedAt: Date

    public init(playlistId: String, videoId: String, position: Int, addedAt: Date = .now) {
        self.playlistId = playlistId; self.videoId = videoId; self.position = position; self.addedAt = addedAt
    }
}

public struct WatchLaterEntry: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "watchLater"
    public var videoId: String
    public var savedAt: Date
    public var pinned: Bool

    public init(videoId: String, savedAt: Date = .now, pinned: Bool = false) {
        self.videoId = videoId; self.savedAt = savedAt; self.pinned = pinned
    }
}

public struct HistoryEntry: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "history"
    public var videoId: String
    public var lastWatchedAt: Date
    public var positionSeconds: Double
    public var durationSeconds: Double

    public init(videoId: String, lastWatchedAt: Date = .now, positionSeconds: Double, durationSeconds: Double) {
        self.videoId = videoId; self.lastWatchedAt = lastWatchedAt
        self.positionSeconds = positionSeconds; self.durationSeconds = durationSeconds
    }

    public var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1, max(0, positionSeconds / durationSeconds))
    }
    public var remainingSeconds: Double { max(0, durationSeconds - positionSeconds) }
}

public struct LikedVideo: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "liked"
    public var videoId: String
    public var likedAt: Date
    public init(videoId: String, likedAt: Date = .now) { self.videoId = videoId; self.likedAt = likedAt }
}

public struct Note: Codable, Hashable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "note"
    public var id: Int64?
    public var videoId: String
    public var time: Double
    public var text: String
    public var createdAt: Date

    public init(id: Int64? = nil, videoId: String, time: Double, text: String, createdAt: Date = .now) {
        self.id = id; self.videoId = videoId; self.time = time; self.text = text; self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Joined rows used by screens

public struct WatchLaterRow: Hashable, Identifiable, Sendable {
    public var entry: WatchLaterEntry
    public var video: Video
    public var id: String { video.id }

    /// 1 = just saved, 0 = about to be cleared.
    public func life(clearAfter weeks: Int, now: Date = .now) -> Double {
        guard !entry.pinned else { return 1 }
        let span = Double(weeks) * 7 * 86_400
        let age = now.timeIntervalSince(entry.savedAt)
        return max(0, min(1, 1 - age / span))
    }

    public func expiresAt(clearAfter weeks: Int) -> Date {
        entry.savedAt.addingTimeInterval(Double(weeks) * 7 * 86_400)
    }
}

public struct HistoryRow: Hashable, Identifiable, Sendable {
    public var entry: HistoryEntry
    public var video: Video
    public var id: String { video.id }
}

public struct PlaylistSummary: Hashable, Identifiable, Sendable {
    public var playlist: Playlist
    public var count: Int
    public var cover: Video?
    public var id: String { playlist.id }
}

// MARK: - Chapters

public struct Chapter: Hashable, Identifiable, Sendable {
    public var index: Int
    public var title: String
    public var start: Double
    public var end: Double
    public var id: Int { index }
    public var length: Double { max(0, end - start) }

    public init(index: Int, title: String, start: Double, end: Double) {
        self.index = index; self.title = title; self.start = start; self.end = end
    }
}

// MARK: - Topics

public struct Topic: Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var categoryId: String?
    public var query: String?

    public static let all: [Topic] = [
        Topic(id: "all", title: "All"),
        Topic(id: "coding", title: "Coding", categoryId: "28", query: "programming"),
        Topic(id: "music", title: "Music", categoryId: "10"),
        Topic(id: "live", title: "Live", query: "live"),
        Topic(id: "science", title: "Science", categoryId: "28", query: "science"),
        Topic(id: "gaming", title: "Gaming", categoryId: "20"),
        Topic(id: "podcasts", title: "Podcasts", query: "podcast"),
        Topic(id: "sport", title: "Sport", categoryId: "17"),
        Topic(id: "cooking", title: "Cooking", categoryId: "26", query: "cooking"),
    ]
}
