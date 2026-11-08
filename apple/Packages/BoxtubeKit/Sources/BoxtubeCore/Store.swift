import Foundation
import GRDB

/// Local SQLite store (GRDB). Everything the app shows is read from here; network refreshes write into it.
public final class Store: Sendable {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public static func live() throws -> Store {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Boxtube", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: folder.appending(path: "boxtube.sqlite").path, configuration: config)
        return try Store(writer: pool)
    }

    public static func inMemory() throws -> Store { try Store(writer: DatabaseQueue()) }

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "channel") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("avatarURL", .text)
                t.column("subscriberCount", .integer)
                t.column("isSubscribed", .boolean).notNull().defaults(to: false)
                t.column("subscribedAt", .datetime)
                t.column("isMusic", .boolean).notNull().defaults(to: false)
                t.column("lastFetchedAt", .datetime)
                t.column("lastSeenAt", .datetime)
            }
            try db.create(table: "video") { t in
                t.primaryKey("id", .text)
                t.column("channelId", .text).notNull().indexed()
                t.column("channelTitle", .text).notNull()
                t.column("title", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("publishedAt", .datetime).notNull().indexed()
                t.column("durationSeconds", .integer)
                t.column("viewCount", .integer)
                t.column("likeCount", .integer)
                t.column("thumbnailURL", .text)
                t.column("isShort", .boolean).notNull().defaults(to: false)
                t.column("isLive", .boolean).notNull().defaults(to: false)
                t.column("categoryId", .text)
                t.column("fetchedAt", .datetime).notNull()
            }
            try db.create(table: "playlist") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("isMusic", .boolean).notNull().defaults(to: false)
                t.column("isPrivate", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "playlistItem") { t in
                t.column("playlistId", .text).notNull().references("playlist", onDelete: .cascade)
                t.column("videoId", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("addedAt", .datetime).notNull()
                t.primaryKey(["playlistId", "videoId"])
            }
            try db.create(table: "watchLater") { t in
                t.primaryKey("videoId", .text)
                t.column("savedAt", .datetime).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "history") { t in
                t.primaryKey("videoId", .text)
                t.column("lastWatchedAt", .datetime).notNull().indexed()
                t.column("positionSeconds", .double).notNull()
                t.column("durationSeconds", .double).notNull()
            }
            try db.create(table: "liked") { t in
                t.primaryKey("videoId", .text)
                t.column("likedAt", .datetime).notNull()
            }
            try db.create(table: "note") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("videoId", .text).notNull().indexed()
                t.column("time", .double).notNull()
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "listCache") { t in
                t.column("key", .text).notNull()
                t.column("videoId", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("fetchedAt", .datetime).notNull()
                t.primaryKey(["key", "videoId"])
            }
        }
        return m
    }

    // MARK: Observation

    /// Re-runs `fetch` whenever a table it reads changes. Use with `for await` in `.task`.
    public func values<T: Sendable>(_ fetch: @escaping @Sendable (Database) throws -> T) -> AsyncValueObservation<T> {
        ValueObservation.tracking(fetch).values(in: writer, scheduling: .async(onQueue: .main))
    }

    public func read<T: Sendable>(_ fetch: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await writer.read(fetch)
    }

    // MARK: Writes

    public func upsert(videos: [Video], preserveDetails: Bool = true) async throws {
        guard !videos.isEmpty else { return }
        try await writer.write { db in
            for var video in videos {
                if preserveDetails, let existing = try Video.fetchOne(db, key: video.id) {
                    video.durationSeconds = video.durationSeconds ?? existing.durationSeconds
                    video.categoryId = video.categoryId ?? existing.categoryId
                    video.likeCount = video.likeCount ?? existing.likeCount
                    video.viewCount = video.viewCount ?? existing.viewCount
                    if video.summary.isEmpty { video.summary = existing.summary }
                    video.isShort = video.isShort || existing.isShort
                }
                try video.save(db)
            }
        }
    }

    public func upsert(channels: [Channel]) async throws {
        try await writer.write { db in
            for var channel in channels {
                if let existing = try Channel.fetchOne(db, key: channel.id) {
                    channel.isSubscribed = existing.isSubscribed
                    channel.subscribedAt = existing.subscribedAt
                    channel.isMusic = existing.isMusic || channel.isMusic
                    channel.lastSeenAt = existing.lastSeenAt
                    channel.lastFetchedAt = channel.lastFetchedAt ?? existing.lastFetchedAt
                    channel.avatarURL = channel.avatarURL ?? existing.avatarURL
                    channel.subscriberCount = channel.subscriberCount ?? existing.subscriberCount
                    if channel.title == channel.id { channel.title = existing.title }
                }
                try channel.save(db)
            }
        }
    }

    public func subscribe(_ channel: Channel, music: Bool = false) async throws {
        try await writer.write { db in
            var c = try Channel.fetchOne(db, key: channel.id) ?? channel
            c.isSubscribed = true
            c.subscribedAt = c.subscribedAt ?? .now
            c.isMusic = c.isMusic || music
            try c.save(db)
        }
    }

    public func unsubscribe(_ channelId: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE channel SET isSubscribed = 0 WHERE id = ?", arguments: [channelId])
        }
    }

    public func markChannelsSeen(_ ids: [String]? = nil) async throws {
        try await writer.write { db in
            if let ids {
                try db.execute(sql: "UPDATE channel SET lastSeenAt = ? WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ",")))",
                               arguments: StatementArguments([Date.now] + ids))
            } else {
                try db.execute(sql: "UPDATE channel SET lastSeenAt = ? WHERE isSubscribed = 1", arguments: [Date.now])
            }
        }
    }

    public func setFetched(channelId: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE channel SET lastFetchedAt = ? WHERE id = ?", arguments: [Date.now, channelId])
        }
    }

    public func toggleWatchLater(_ videoId: String) async throws {
        try await writer.write { db in
            if try WatchLaterEntry.exists(db, key: videoId) {
                _ = try WatchLaterEntry.deleteOne(db, key: videoId)
            } else {
                try WatchLaterEntry(videoId: videoId).insert(db)
            }
        }
    }

    public func setPinned(_ videoId: String, pinned: Bool) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE watchLater SET pinned = ? WHERE videoId = ?", arguments: [pinned, videoId])
        }
    }

    public func keepWatchLater(_ ids: [String]) async throws {
        try await writer.write { db in
            for id in ids { try db.execute(sql: "UPDATE watchLater SET savedAt = ? WHERE videoId = ?", arguments: [Date.now, id]) }
        }
    }

    /// Idea 02: entries older than `weeks` leave the list unless pinned.
    @discardableResult
    public func purgeWatchLater(olderThan weeks: Int) async throws -> Int {
        let cutoff = Date.now.addingTimeInterval(-Double(weeks) * 7 * 86_400)
        return try await writer.write { db in
            try db.execute(sql: "DELETE FROM watchLater WHERE pinned = 0 AND savedAt < ?", arguments: [cutoff])
            return db.changesCount
        }
    }

    public func recordProgress(videoId: String, position: Double, duration: Double) async throws {
        guard duration > 0 else { return }
        try await writer.write { db in
            try HistoryEntry(videoId: videoId, positionSeconds: position, durationSeconds: duration).save(db)
            if duration > 0 {
                try db.execute(sql: "UPDATE video SET durationSeconds = COALESCE(durationSeconds, ?) WHERE id = ?",
                               arguments: [Int(duration), videoId])
            }
        }
    }

    public func clearHistory() async throws {
        try await writer.write { db in _ = try HistoryEntry.deleteAll(db) }
    }

    public func toggleLike(_ videoId: String) async throws {
        try await writer.write { db in
            if try LikedVideo.exists(db, key: videoId) {
                _ = try LikedVideo.deleteOne(db, key: videoId)
            } else {
                try LikedVideo(videoId: videoId).insert(db)
            }
        }
    }

    @discardableResult
    public func createPlaylist(title: String, music: Bool = false) async throws -> Playlist {
        let playlist = Playlist(title: title, isMusic: music)
        try await writer.write { db in try playlist.insert(db) }
        return playlist
    }

    public func deletePlaylist(_ id: String) async throws {
        try await writer.write { db in _ = try Playlist.deleteOne(db, key: id) }
    }

    public func add(videoId: String, toPlaylist playlistId: String) async throws {
        try await writer.write { db in
            let next = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM playlistItem WHERE playlistId = ?", arguments: [playlistId]) ?? 0
            try PlaylistItem(playlistId: playlistId, videoId: videoId, position: next).insert(db, onConflict: .ignore)
            try db.execute(sql: "UPDATE playlist SET updatedAt = ? WHERE id = ?", arguments: [Date.now, playlistId])
        }
    }

    public func remove(videoId: String, fromPlaylist playlistId: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM playlistItem WHERE playlistId = ? AND videoId = ?", arguments: [playlistId, videoId])
        }
    }

    @discardableResult
    public func addNote(videoId: String, time: Double, text: String) async throws -> Note {
        try await writer.write { db in
            var note = Note(videoId: videoId, time: time, text: text)
            try note.insert(db)
            return note
        }
    }

    public func deleteNote(_ id: Int64) async throws {
        try await writer.write { db in _ = try Note.deleteOne(db, key: id) }
    }

    public func cache(list key: String, videoIds: [String]) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM listCache WHERE key = ?", arguments: [key])
            for (i, id) in videoIds.enumerated() {
                try db.execute(sql: "INSERT OR REPLACE INTO listCache (key, videoId, position, fetchedAt) VALUES (?, ?, ?, ?)",
                               arguments: [key, id, i, Date.now])
            }
        }
    }
}

// MARK: - Queries (pure functions over a Database, used with `values` and `read`)

public enum Q {
    public static func video(_ db: Database, _ id: String) throws -> Video? { try Video.fetchOne(db, key: id) }

    public static func feed(_ db: Database, music: Bool = false, limit: Int = 60) throws -> [Video] {
        try Video.fetchAll(db, sql: """
            SELECT video.* FROM video JOIN channel ON channel.id = video.channelId
            WHERE channel.isSubscribed = 1 AND video.isShort = 0 AND channel.isMusic = ?
            ORDER BY video.publishedAt DESC LIMIT ?
            """, arguments: [music, limit])
    }

    public static func shorts(_ db: Database, limit: Int = 40) throws -> [Video] {
        try Video.fetchAll(db, sql: """
            SELECT video.* FROM video LEFT JOIN channel ON channel.id = video.channelId
            WHERE video.isShort = 1 AND (channel.isSubscribed = 1 OR video.id IN (SELECT videoId FROM listCache WHERE key = 'shorts'))
            ORDER BY video.publishedAt DESC LIMIT ?
            """, arguments: [limit])
    }

    public static func cachedList(_ db: Database, key: String) throws -> [Video] {
        try Video.fetchAll(db, sql: """
            SELECT video.* FROM listCache JOIN video ON video.id = listCache.videoId
            WHERE listCache.key = ? ORDER BY listCache.position
            """, arguments: [key])
    }

    public static func cacheAge(_ db: Database, key: String) throws -> Date? {
        try Date.fetchOne(db, sql: "SELECT MAX(fetchedAt) FROM listCache WHERE key = ?", arguments: [key])
    }

    public struct SubscriptionRow: Hashable, Identifiable, Sendable {
        public var channel: Channel
        public var newCount: Int
        public var isLive: Bool
        public var id: String { channel.id }
    }

    public static func subscriptions(_ db: Database, music: Bool? = nil) throws -> [SubscriptionRow] {
        let channels = try Channel.fetchAll(db, sql: """
            SELECT * FROM channel WHERE isSubscribed = 1 \(music.map { "AND isMusic = \($0 ? 1 : 0)" } ?? "")
            ORDER BY title COLLATE NOCASE
            """)
        return try channels.map { c in
            let newCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM video WHERE channelId = ? AND publishedAt > ? AND isShort = 0",
                                            arguments: [c.id, c.lastSeenAt ?? c.subscribedAt ?? .distantPast]) ?? 0
            let live = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM video WHERE channelId = ? AND isLive = 1)", arguments: [c.id]) ?? false
            return SubscriptionRow(channel: c, newCount: newCount, isLive: live)
        }
        .sorted { ($0.isLive ? 0 : 1, $0.newCount > 0 ? 0 : 1) < ($1.isLive ? 0 : 1, $1.newCount > 0 ? 0 : 1) }
    }

    public static func channelVideos(_ db: Database, channelId: String) throws -> [Video] {
        try Video.filter(Column("channelId") == channelId).order(Column("publishedAt").desc).fetchAll(db)
    }

    public static func watchLater(_ db: Database) throws -> [WatchLaterRow] {
        let entries = try WatchLaterEntry.order(Column("pinned").desc, Column("savedAt").desc).fetchAll(db)
        let videos = try Video.fetchAll(db, keys: entries.map(\.videoId))
        let byId = Dictionary(uniqueKeysWithValues: videos.map { ($0.id, $0) })
        return entries.compactMap { e in byId[e.videoId].map { WatchLaterRow(entry: e, video: $0) } }
    }

    public static func watchLaterIds(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT videoId FROM watchLater"))
    }

    public static func likedIds(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT videoId FROM liked"))
    }

    public static func liked(_ db: Database, music: Bool? = nil) throws -> [Video] {
        let filter = music.map { " AND COALESCE(video.categoryId, '') \($0 ? "=" : "<>") '10'" } ?? ""
        return try Video.fetchAll(db, sql: "SELECT video.* FROM liked JOIN video ON video.id = liked.videoId WHERE 1=1\(filter) ORDER BY liked.likedAt DESC")
    }

    public static func history(_ db: Database, limit: Int = 30, unfinishedOnly: Bool = false) throws -> [HistoryRow] {
        let entries = try HistoryEntry.order(Column("lastWatchedAt").desc).limit(limit * 2).fetchAll(db)
            .filter { !unfinishedOnly || ($0.progress > 0.02 && $0.progress < 0.95) }
        let videos = try Video.fetchAll(db, keys: entries.map(\.videoId))
        let byId = Dictionary(uniqueKeysWithValues: videos.map { ($0.id, $0) })
        return Array(entries.compactMap { e in byId[e.videoId].map { HistoryRow(entry: e, video: $0) } }.prefix(limit))
    }

    public static func progress(_ db: Database) throws -> [String: Double] {
        let entries = try HistoryEntry.fetchAll(db)
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.videoId, $0.progress) })
    }

    public static func playlists(_ db: Database, music: Bool? = nil) throws -> [PlaylistSummary] {
        var request = Playlist.order(Column("updatedAt").desc)
        if let music { request = request.filter(Column("isMusic") == music) }
        return try request.fetchAll(db).map { p in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM playlistItem WHERE playlistId = ?", arguments: [p.id]) ?? 0
            let cover = try Video.fetchOne(db, sql: """
                SELECT video.* FROM playlistItem JOIN video ON video.id = playlistItem.videoId
                WHERE playlistId = ? ORDER BY position LIMIT 1
                """, arguments: [p.id])
            return PlaylistSummary(playlist: p, count: count, cover: cover)
        }
    }

    public static func playlistVideos(_ db: Database, id: String) throws -> [Video] {
        try Video.fetchAll(db, sql: """
            SELECT video.* FROM playlistItem JOIN video ON video.id = playlistItem.videoId
            WHERE playlistId = ? ORDER BY position
            """, arguments: [id])
    }

    public static func notes(_ db: Database, videoId: String) throws -> [Note] {
        try Note.filter(Column("videoId") == videoId).order(Column("time")).fetchAll(db)
    }

    public static func allNotesCount(_ db: Database) throws -> Int { try Note.fetchCount(db) }

    public struct Stats: Sendable, Hashable {
        public var watchedThisWeek: Double
        public var playlists: Int
        public var subscriptions: Int
        public var notes: Int
    }

    public static func stats(_ db: Database) throws -> Stats {
        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        let watched = try Double.fetchOne(db, sql: "SELECT COALESCE(SUM(positionSeconds), 0) FROM history WHERE lastWatchedAt > ?", arguments: [weekAgo]) ?? 0
        return Stats(
            watchedThisWeek: watched,
            playlists: try Playlist.fetchCount(db),
            subscriptions: try Channel.filter(Column("isSubscribed") == true).fetchCount(db),
            notes: try Note.fetchCount(db)
        )
    }
}
