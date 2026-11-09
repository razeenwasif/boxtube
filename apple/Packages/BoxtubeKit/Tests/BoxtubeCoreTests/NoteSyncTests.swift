import Testing
import Foundation
import GRDB
@testable import BoxtubeCore

/// The database side of syncing notes through iCloud (the CloudKit side needs a signed app).
@Suite("Note sync")
struct NoteSyncTests {
    let when = Date(timeIntervalSince1970: 1_800_000_000)

    func remote(_ uuid: String, video: String = "vid", text: String = "Remember this", time: Double = 42) -> SyncedNote {
        SyncedNote(uuid: uuid, videoId: video, time: time, text: text, createdAt: when,
                   videoTitle: "A video from elsewhere", channelId: "chan", channelTitle: "Chan", publishedAt: when)
    }

    @Test func notesGetSharedIds() async throws {
        let store = try Store.inMemory()
        let a = try await store.addNote(videoId: "v", time: 1, text: "one")
        let b = try await store.addNote(videoId: "v", time: 2, text: "two")
        #expect(!a.uuid.isEmpty && a.uuid != b.uuid)
        #expect(Set(try await store.allNoteUUIDs()) == [a.uuid, b.uuid])
    }

    @Test func deletingReturnsTheSharedId() async throws {
        let store = try Store.inMemory()
        let note = try await store.addNote(videoId: "v", time: 1, text: "gone soon")
        #expect(try await store.deleteNote(note.id!) == note.uuid)
        #expect(try await store.allNoteUUIDs().isEmpty)
    }

    @Test func remoteNotesArriveWithTheirVideo() async throws {
        let store = try Store.inMemory()
        let newVideos = try await store.applyRemote(notes: [remote("n1")], deleted: [])
        #expect(newVideos == ["vid"])
        let (notes, video) = try await store.read { db in (try Q.notes(db, videoId: "vid"), try Video.fetchOne(db, key: "vid")) }
        #expect(notes.map(\.uuid) == ["n1"])
        #expect(notes.first?.text == "Remember this")
        #expect(video?.title == "A video from elsewhere")
    }

    @Test func applyingTheSameNoteTwiceKeepsOneCopy() async throws {
        let store = try Store.inMemory()
        try await store.applyRemote(notes: [remote("n1")], deleted: [])
        let again = try await store.applyRemote(notes: [remote("n1", text: "Remember this, edited")], deleted: [])
        #expect(again.isEmpty)
        let notes = try await store.read { db in try Q.notes(db, videoId: "vid") }
        #expect(notes.count == 1)
        #expect(notes.first?.text == "Remember this, edited")
    }

    @Test func remoteDeletionsRemoveLocalNotes() async throws {
        let store = try Store.inMemory()
        let mine = try await store.addNote(videoId: "vid", time: 3, text: "mine")
        try await store.applyRemote(notes: [remote("n1")], deleted: [mine.uuid])
        #expect(try await store.allNoteUUIDs() == ["n1"])
    }

    @Test func outgoingNotesCarryTheirVideo() async throws {
        let store = try Store.inMemory()
        try await store.upsert(videos: [Video(id: "v", channelId: "c", channelTitle: "Channel", title: "Title", publishedAt: when)])
        let note = try await store.addNote(videoId: "v", time: 9, text: "hi")
        let out = try await store.syncedNotes(uuids: [note.uuid, "missing"])
        #expect(out.count == 1)
        #expect(out[note.uuid]?.videoTitle == "Title")
        #expect(out[note.uuid]?.channelTitle == "Channel")
    }

    @Test func syncStateRoundTrips() async throws {
        let store = try Store.inMemory()
        try await store.setSyncState("notes", Data([1, 2, 3]))
        #expect(try await store.syncState("notes") == Data([1, 2, 3]))
        try await store.setSyncState("notes", nil)
        #expect(try await store.syncState("notes") == nil)
    }
}
