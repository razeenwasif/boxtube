import Foundation
import GRDB

/// A note as it travels through iCloud: the note itself plus enough about its video for a device
/// that has never seen that video to list it on the Notes page.
public struct SyncedNote: Sendable, Hashable {
    public var uuid: String
    public var videoId: String
    public var time: Double
    public var text: String
    public var createdAt: Date
    public var videoTitle: String
    public var channelId: String
    public var channelTitle: String
    public var publishedAt: Date

    public init(uuid: String, videoId: String, time: Double, text: String, createdAt: Date,
                videoTitle: String, channelId: String, channelTitle: String, publishedAt: Date) {
        self.uuid = uuid; self.videoId = videoId; self.time = time; self.text = text; self.createdAt = createdAt
        self.videoTitle = videoTitle; self.channelId = channelId; self.channelTitle = channelTitle; self.publishedAt = publishedAt
    }
}

extension Store {
    // MARK: Sync engine state

    public func syncState(_ key: String) async throws -> Data? {
        try await writer.read { db in try Data.fetchOne(db, sql: "SELECT data FROM syncState WHERE key = ?", arguments: [key]) }
    }

    public func setSyncState(_ key: String, _ data: Data?) async throws {
        try await writer.write { db in
            if let data {
                try db.execute(sql: "INSERT OR REPLACE INTO syncState (key, data) VALUES (?, ?)", arguments: [key, data])
            } else {
                try db.execute(sql: "DELETE FROM syncState WHERE key = ?", arguments: [key])
            }
        }
    }

    // MARK: Notes for iCloud

    public func allNoteUUIDs() async throws -> [String] {
        try await writer.read { db in try String.fetchAll(db, sql: "SELECT uuid FROM note") }
    }

    /// The notes with these ids, with their videos, keyed by id. Ids that no longer exist are left out.
    public func syncedNotes(uuids: [String]) async throws -> [String: SyncedNote] {
        guard !uuids.isEmpty else { return [:] }
        return try await writer.read { db in
            let notes = try Note.filter(uuids.contains(Column("uuid"))).fetchAll(db)
            var out: [String: SyncedNote] = [:]
            for n in notes {
                let v = try Video.fetchOne(db, key: n.videoId)
                out[n.uuid] = SyncedNote(uuid: n.uuid, videoId: n.videoId, time: n.time, text: n.text, createdAt: n.createdAt,
                                         videoTitle: v?.title ?? "", channelId: v?.channelId ?? "", channelTitle: v?.channelTitle ?? "",
                                         publishedAt: v?.publishedAt ?? n.createdAt)
            }
            return out
        }
    }

    /// Applies notes and deletions that came from another device. Returns the ids of videos that weren't
    /// in the store before, so their details can be fetched.
    @discardableResult
    public func applyRemote(notes: [SyncedNote], deleted: [String]) async throws -> [String] {
        try await writer.write { db in
            var newVideos: [String] = []
            for r in notes {
                if try Video.fetchOne(db, key: r.videoId) == nil {
                    let video = Video(id: r.videoId, channelId: r.channelId, channelTitle: r.channelTitle,
                                      title: r.videoTitle.isEmpty ? "Video" : r.videoTitle, publishedAt: r.publishedAt)
                    try Self.upsert(videos: [video], preserveDetails: true, in: db)
                    newVideos.append(r.videoId)
                }
                if var existing = try Note.filter(Column("uuid") == r.uuid).fetchOne(db) {
                    existing.videoId = r.videoId; existing.time = r.time; existing.text = r.text; existing.createdAt = r.createdAt
                    try existing.update(db)
                } else {
                    var note = Note(uuid: r.uuid, videoId: r.videoId, time: r.time, text: r.text, createdAt: r.createdAt)
                    try note.insert(db)
                }
            }
            if !deleted.isEmpty {
                _ = try Note.filter(deleted.contains(Column("uuid"))).deleteAll(db)
            }
            return newVideos
        }
    }
}
