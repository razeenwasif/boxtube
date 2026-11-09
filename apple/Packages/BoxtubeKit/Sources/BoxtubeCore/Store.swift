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
        m.registerMigration("v2-playlist-music-choice") { db in
            try db.alter(table: "playlist") { t in t.add(column: "musicChosen", .boolean).notNull().defaults(to: false) }
        }
        m.registerMigration("v3-channel-music-choice") { db in
            try db.alter(table: "channel") { t in t.add(column: "musicChosen", .boolean).notNull().defaults(to: false) }
        }
        m.registerMigration("v4-outbox") { db in
            try db.create(table: "outbox") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("target", .text).notNull()
                t.column("playlistId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("lastError", .text)
            }
        }
        m.registerMigration("v5-hidden-playlists") { db in
            // YouTube playlists you removed from Boxtube, so an import doesn't bring them back.
            try db.create(table: "hiddenPlaylist") { t in t.primaryKey("id", .text) }
        }
        m.registerMigration("v6-not-interested") { db in
            // "Not interested" videos and "Don't recommend" channels, left out of Home, topics, search and Shorts.
            try db.create(table: "hiddenVideo") { t in
                t.primaryKey("id", .text)
                t.column("hiddenAt", .datetime).notNull()
            }
            try db.create(table: "hiddenChannel") { t in
                t.primaryKey("id", .text)
                t.column("hiddenAt", .datetime).notNull()
            }
        }
        return m
    }

    // MARK: Observation

    /// Re-runs `fetch` whenever a table it reads changes. Use with `for await` in `.task`.
    public func values<T: Sendable>(_ fetch: @escaping @Sendable (Database) throws -> T) -> AsyncValueObservation<T> {
        ValueObservation.tracking(fetch).values(in: writer, scheduling: .async(onQueue: .main))
    }

    /// For comparable results: skips writes that don't change the answer (saving progress doesn't touch the
    /// feed's videos, for example), so screens aren't redrawn for nothing.
    public func values<T: Sendable & Equatable>(_ fetch: @escaping @Sendable (Database) throws -> T) -> AsyncValueObservation<T> {
        ValueObservation.tracking(fetch).removeDuplicates().values(in: writer, scheduling: .async(onQueue: .main))
    }

    public func read<T: Sendable>(_ fetch: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await writer.read(fetch)
    }

    // MARK: Writes

    public func upsert(videos: [Video], preserveDetails: Bool = true) async throws {
        guard !videos.isEmpty else { return }
        try await writer.write { db in try Self.upsert(videos: videos, preserveDetails: preserveDetails, in: db) }
    }

    public func upsert(channels: [Channel]) async throws {
        try await writer.write { db in try Self.upsert(channels: channels, in: db) }
    }

    /// Saves fetched channel feeds in one transaction and marks them fetched. Writing per channel woke
    /// every open screen's query hundreds of times during a refresh.
    public func saveFeeds(_ feeds: [(channel: Channel, videos: [Video])]) async throws {
        guard !feeds.isEmpty else { return }
        try await writer.write { db in
            let now = Date.now
            for feed in feeds {
                try Self.upsert(channels: [feed.channel], in: db)
                try Self.upsert(videos: feed.videos, preserveDetails: true, in: db)
                try db.execute(sql: "UPDATE channel SET lastFetchedAt = ? WHERE id = ?", arguments: [now, feed.channel.id])
            }
        }
    }

    /// Skips rows that wouldn't change, so a refresh that finds nothing new doesn't count as a change.
    static func upsert(videos: [Video], preserveDetails: Bool, in db: Database) throws {
        for var video in videos {
            if let existing = try Video.fetchOne(db, key: video.id) {
                if preserveDetails {
                    video.durationSeconds = video.durationSeconds ?? existing.durationSeconds
                    video.categoryId = video.categoryId ?? existing.categoryId
                    video.likeCount = video.likeCount ?? existing.likeCount
                    video.viewCount = video.viewCount ?? existing.viewCount
                    if video.summary.isEmpty { video.summary = existing.summary }
                    video.isShort = video.isShort || existing.isShort
                }
                var same = video
                same.fetchedAt = existing.fetchedAt
                if same == existing { continue }
            }
            try video.save(db)
        }
    }

    static func upsert(channels: [Channel], in db: Database) throws {
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
                if channel == existing { continue }
            }
            try channel.save(db)
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

    // MARK: Outbox (two-way sync)

    /// Playlists made in Boxtube have UUID ids; YouTube's own look like "PL…".
    public static func isLocalPlaylist(_ id: String) -> Bool { UUID(uuidString: id) != nil }

    /// Queues a change for YouTube. A newer change replaces any waiting one it overrides
    /// (like then unlike sends only the unlike; add then remove the same video sends only the remove).
    public func enqueue(_ kind: OutboxOp.Kind, target: String, playlistId: String? = nil) async throws {
        try await writer.write { db in
            let family = OutboxOp.Kind.allCases.filter { $0.family == kind.family }.map(\.rawValue)
            if kind != .playlistCreate {
                try db.execute(sql: """
                    DELETE FROM outbox WHERE target = ? AND kind IN (\(family.map { _ in "?" }.joined(separator: ",")))
                    AND COALESCE(playlistId, '') = COALESCE(?, '')
                    """, arguments: StatementArguments([target] + family + [playlistId]))
            }
            var op = OutboxOp(kind: kind, target: target, playlistId: playlistId)
            try op.insert(db)
        }
    }

    public func finishOutbox(_ id: Int64) async throws {
        try await writer.write { db in _ = try OutboxOp.deleteOne(db, key: id) }
    }

    public func failOutbox(_ id: Int64, error: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE outbox SET attempts = attempts + 1, lastError = ? WHERE id = ?", arguments: [error, id])
        }
    }

    /// Gives up on changes YouTube kept refusing.
    public func clearFailedOutbox() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM outbox WHERE attempts >= ?", arguments: [SyncService.maxAttempts])
        }
    }

    /// After a Boxtube playlist is created on YouTube, it takes YouTube's id everywhere.
    public func rekeyPlaylist(from old: String, to new: String) async throws {
        try await writer.write { db in
            guard var playlist = try Playlist.fetchOne(db, key: old) else { return }
            playlist.id = new
            try playlist.insert(db, onConflict: .replace)
            try db.execute(sql: "UPDATE playlistItem SET playlistId = ? WHERE playlistId = ?", arguments: [new, old])
            try db.execute(sql: "UPDATE outbox SET playlistId = ? WHERE playlistId = ?", arguments: [new, old])
            _ = try Playlist.deleteOne(db, key: old)
        }
    }

    /// "Show in Music" for a channel: moves it between the Videos feed and Music's artists, and remembers the choice.
    public func setChannelMusic(_ id: String, _ music: Bool) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE channel SET isMusic = ?, musicChosen = 1 WHERE id = ?", arguments: [music, id])
        }
    }

    /// Flags subscribed channels that are clearly music artists: YouTube's "- Topic" and VEVO channels, or
    /// channels whose known videos are at least 70% Music category (3+ videos). Never overrides your choice.
    @discardableResult
    public func detectMusicChannels() async throws -> Int {
        try await writer.write { db in
            try db.execute(sql: """
                UPDATE channel SET isMusic = 1
                WHERE isSubscribed = 1 AND isMusic = 0 AND musicChosen = 0 AND (
                    title LIKE '% - Topic' OR title LIKE '%VEVO' OR id IN (
                        SELECT channelId FROM video WHERE categoryId IS NOT NULL GROUP BY channelId
                        HAVING COUNT(*) >= 3 AND SUM(CASE WHEN categoryId = '10' THEN 1 ELSE 0 END) * 1.0 / COUNT(*) >= 0.7))
                """)
            return db.changesCount
        }
    }

    /// "Show in Music": puts a playlist in Music mode's library (or takes it out) and remembers the choice.
    public func setPlaylistMusic(_ id: String, _ music: Bool) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE playlist SET isMusic = ?, musicChosen = 1 WHERE id = ?", arguments: [music, id])
        }
    }

    /// Removes a playlist from Boxtube. A YouTube playlist is remembered as removed, so imports leave it out;
    /// with `onYouTube` it's also queued for deletion there. Queued edits to it are dropped either way.
    public func deletePlaylist(_ id: String, onYouTube: Bool = false) async throws {
        try await writer.write { db in
            let createdHere = try OutboxOp.filter(Column("kind") == OutboxOp.Kind.playlistCreate.rawValue && Column("target") == id).fetchCount(db) > 0
            try db.execute(sql: "DELETE FROM outbox WHERE playlistId = ? OR target = ?", arguments: [id, id])
            _ = try Playlist.deleteOne(db, key: id)
            // A playlist that never reached YouTube (made here, not yet sent) has nothing to hide or delete there.
            guard !Store.isLocalPlaylist(id), !createdHere else { return }
            try db.execute(sql: "INSERT OR IGNORE INTO hiddenPlaylist (id) VALUES (?)", arguments: [id])
            if onYouTube {
                var op = OutboxOp(kind: .playlistDelete, target: id)
                try op.insert(db)
            }
        }
    }

    // MARK: Not interested, watched

    public func hideVideo(_ id: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO hiddenVideo (id, hiddenAt) VALUES (?, ?)", arguments: [id, Date.now])
        }
    }

    public func hideChannel(_ id: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO hiddenChannel (id, hiddenAt) VALUES (?, ?)", arguments: [id, Date.now])
        }
    }

    /// Shows every "Not interested" video and "Don't recommend" channel again.
    public func unhideAll() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM hiddenVideo")
            try db.execute(sql: "DELETE FROM hiddenChannel")
        }
    }

    /// Marks a video watched (full progress) or unwatched (no history).
    public func setWatched(_ video: Video, _ watched: Bool) async throws {
        try await writer.write { db in
            if watched {
                let d = Double(video.durationSeconds ?? 1)
                try HistoryEntry(videoId: video.id, positionSeconds: d, durationSeconds: d).save(db)
            } else {
                _ = try HistoryEntry.deleteOne(db, key: video.id)
            }
        }
    }

    /// Lets imports bring back YouTube playlists you removed from Boxtube.
    public func unhidePlaylists() async throws {
        try await writer.write { db in try db.execute(sql: "DELETE FROM hiddenPlaylist") }
    }

    /// Queues a Boxtube-only playlist for YouTube: made there (private), then its videos added in order.
    /// Returns how many videos will be added.
    @discardableResult
    public func publishPlaylist(_ id: String) async throws -> Int {
        try await writer.write { db in
            guard Store.isLocalPlaylist(id), try Playlist.exists(db, key: id) else { return 0 }
            let already = try OutboxOp.filter(Column("kind") == OutboxOp.Kind.playlistCreate.rawValue && Column("target") == id).fetchCount(db)
            guard already == 0 else { return 0 }
            var create = OutboxOp(kind: .playlistCreate, target: id)
            try create.insert(db)
            let videos = try String.fetchAll(db, sql: "SELECT videoId FROM playlistItem WHERE playlistId = ? ORDER BY position", arguments: [id])
            for v in videos {
                var add = OutboxOp(kind: .playlistAdd, target: v, playlistId: id)
                try add.insert(db)
            }
            return videos.count
        }
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
    /// Brings in what's on your YouTube account. Subscriptions and likes are added; your playlists are
    /// mirrored (same ids, items replaced). Starter channels you don't follow on YouTube are dropped.
    public func importAccount(subscriptions: [Channel], playlists: [(YouTubeClient.AccountPlaylist, [String])],
                              likedIds: [String], starterIds: Set<String>, mirrorSubscriptions: Bool = false) async throws {
        try await writer.write { db in
            let subscribed = Set(subscriptions.map(\.id))
            let waiting = try OutboxOp.fetchAll(db)
            for channel in subscriptions {
                var c = try Channel.fetchOne(db, key: channel.id) ?? channel
                c.title = channel.title
                c.avatarURL = channel.avatarURL ?? c.avatarURL
                c.isSubscribed = true
                c.subscribedAt = c.subscribedAt ?? .now
                try c.save(db)
            }
            // With sync on, YouTube is the record: channels you've left there are left here too,
            // unless a subscribe from Boxtube is still on its way.
            var toDrop = starterIds.subtracting(subscribed)
            if mirrorSubscriptions {
                let pending = Set(waiting.filter { $0.kind == .subscribe }.map(\.target))
                let local = try String.fetchAll(db, sql: "SELECT id FROM channel WHERE isSubscribed = 1")
                toDrop.formUnion(Set(local).subtracting(subscribed).subtracting(pending))
            }
            for id in toDrop {
                try db.execute(sql: "UPDATE channel SET isSubscribed = 0 WHERE id = ?", arguments: [id])
            }
            let hidden = Set(try String.fetchAll(db, sql: "SELECT id FROM hiddenPlaylist"))
            for (remote, videoIds) in playlists where !hidden.contains(remote.id) {
                let existing = try Playlist.fetchOne(db, key: remote.id)
                var playlist = Playlist(id: remote.id, title: remote.title, isMusic: existing?.isMusic ?? false, isPrivate: remote.isPrivate,
                                        createdAt: existing?.createdAt ?? .now, updatedAt: .now, musicChosen: existing?.musicChosen ?? false)
                try playlist.save(db)
                try db.execute(sql: "DELETE FROM playlistItem WHERE playlistId = ?", arguments: [remote.id])
                for (i, vid) in videoIds.uniqued().enumerated() {
                    try PlaylistItem(playlistId: remote.id, videoId: vid, position: i).insert(db, onConflict: .ignore)
                }
                // YouTube doesn't mark music playlists, so guess from the videos: mostly Music category → Music mode.
                if !playlist.musicChosen {
                    let row = try Row.fetchOne(db, sql: """
                        SELECT COUNT(*) AS total, SUM(CASE WHEN video.categoryId = '10' THEN 1 ELSE 0 END) AS music
                        FROM playlistItem JOIN video ON video.id = playlistItem.videoId WHERE playlistId = ?
                        """, arguments: [remote.id])
                    let total: Int = row?["total"] ?? 0
                    let music: Int = row?["music"] ?? 0
                    playlist.isMusic = total > 0 && Double(music) / Double(total) >= 0.5
                    try playlist.update(db)
                }
            }
            let now = Date.now
            for (i, vid) in likedIds.enumerated() where try !LikedVideo.exists(db, key: vid) {
                try LikedVideo(videoId: vid, likedAt: now.addingTimeInterval(-Double(i))).insert(db)
            }
            // Changes still waiting to reach YouTube stay visible here.
            for op in waiting {
                switch op.kind {
                case .unrate, .dislike: _ = try LikedVideo.deleteOne(db, key: op.target)
                case .unsubscribe: try db.execute(sql: "UPDATE channel SET isSubscribed = 0 WHERE id = ?", arguments: [op.target])
                case .playlistAdd:
                    guard let pl = op.playlistId else { continue }
                    let next = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM playlistItem WHERE playlistId = ?", arguments: [pl]) ?? 0
                    try PlaylistItem(playlistId: pl, videoId: op.target, position: next).insert(db, onConflict: .ignore)
                case .playlistRemove:
                    try db.execute(sql: "DELETE FROM playlistItem WHERE playlistId = ? AND videoId = ?", arguments: [op.playlistId, op.target])
                default: continue
                }
            }
        }
    }

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
              AND video.id NOT IN (SELECT id FROM hiddenVideo)
            ORDER BY video.publishedAt DESC LIMIT ?
            """, arguments: [music, limit])
    }

    public static func shorts(_ db: Database, limit: Int = 40) throws -> [Video] {
        try Video.fetchAll(db, sql: """
            SELECT video.* FROM video LEFT JOIN channel ON channel.id = video.channelId
            WHERE video.isShort = 1 AND (channel.isSubscribed = 1 OR video.id IN (SELECT videoId FROM listCache WHERE key = 'shorts'))
              AND video.id NOT IN (SELECT id FROM hiddenVideo) AND video.channelId NOT IN (SELECT id FROM hiddenChannel)
            ORDER BY video.publishedAt DESC LIMIT ?
            """, arguments: [limit])
    }

    public static func cachedList(_ db: Database, key: String) throws -> [Video] {
        try Video.fetchAll(db, sql: """
            SELECT video.* FROM listCache JOIN video ON video.id = listCache.videoId
            WHERE listCache.key = ? AND video.id NOT IN (SELECT id FROM hiddenVideo) AND video.channelId NOT IN (SELECT id FROM hiddenChannel)
            ORDER BY listCache.position
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
        // Whole percents: progress is saved every 5 s while playing, and finer steps would redraw every
        // card grid for changes too small to see.
        let entries = try HistoryEntry.fetchAll(db)
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.videoId, ($0.progress * 100).rounded() / 100) })
    }

    public static func playlists(_ db: Database, music: Bool? = nil) throws -> [PlaylistSummary] {
        var request = Playlist.order(Column("updatedAt").desc)
        if let music { request = request.filter(Column("isMusic") == music) }
        return try request.fetchAll(db).map { p in
            // Only videos Boxtube can show (deleted or private ones have no details), so the count matches the list.
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM playlistItem JOIN video ON video.id = playlistItem.videoId WHERE playlistId = ?", arguments: [p.id]) ?? 0
            let cover = try Video.fetchOne(db, sql: """
                SELECT video.* FROM playlistItem JOIN video ON video.id = playlistItem.videoId
                WHERE playlistId = ? ORDER BY position LIMIT 1
                """, arguments: [p.id])
            return PlaylistSummary(playlist: p, count: count, cover: cover)
        }
    }

    /// The oldest change still worth sending (ones YouTube kept refusing are set aside).
    public static func nextOutboxOp(_ db: Database, skipping skipped: Set<Int64> = []) throws -> OutboxOp? {
        try OutboxOp.filter(Column("attempts") < SyncService.maxAttempts)
            .filter(!skipped.contains(Column("id")))
            .order(Column("id")).fetchOne(db)
    }

    public struct OutboxSummary: Sendable, Equatable {
        public var waiting = 0
        public var failed = 0
        public var lastError: String?
        public init(waiting: Int = 0, failed: Int = 0, lastError: String? = nil) {
            self.waiting = waiting; self.failed = failed; self.lastError = lastError
        }
    }

    public static func outboxSummary(_ db: Database) throws -> OutboxSummary {
        let all = try OutboxOp.fetchAll(db)
        let failed = all.filter { $0.attempts >= SyncService.maxAttempts }
        return OutboxSummary(waiting: all.count - failed.count, failed: failed.count, lastError: failed.last?.lastError)
    }

    public struct HiddenSets: Sendable, Equatable {
        public var videos: Set<String> = []
        public var channels: Set<String> = []
        public init(videos: Set<String> = [], channels: Set<String> = []) { self.videos = videos; self.channels = channels }
        public var isEmpty: Bool { videos.isEmpty && channels.isEmpty }
    }

    public static func hidden(_ db: Database) throws -> HiddenSets {
        HiddenSets(videos: Set(try String.fetchAll(db, sql: "SELECT id FROM hiddenVideo")),
                   channels: Set(try String.fetchAll(db, sql: "SELECT id FROM hiddenChannel")))
    }

    public static func hiddenPlaylistCount(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hiddenPlaylist") ?? 0
    }

    /// Boxtube-only playlists already queued to be made on YouTube.
    public static func publishingPlaylists(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT target FROM outbox WHERE kind = ?", arguments: [OutboxOp.Kind.playlistCreate.rawValue]))
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
