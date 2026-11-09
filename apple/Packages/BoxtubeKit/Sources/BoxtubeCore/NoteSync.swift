import Foundation
import CloudKit
import os

/// Keeps notes in step across your devices through your private iCloud database. Each note is one
/// `Note` record in a "Notes" zone; `CKSyncEngine` sends local changes, fetches remote ones, retries
/// when offline, and wakes on iCloud pushes. Notes are only ever added or deleted, never edited.
public actor NoteSync: CKSyncEngineDelegate {
    public enum Status: Sendable, Equatable {
        case starting, on, noAccount, failed(String)
    }

    private static let zoneID = CKRecordZone.ID(zoneName: "Notes")
    private static let stateKey = "notes"
    private static let log = Logger(subsystem: "com.razeenwasif.boxtube", category: "NoteSync")

    private let store: Store
    private let containerID: String
    private var engine: CKSyncEngine?
    /// Called with ids of videos a synced note brought in, so their details can be fetched.
    private let onNewVideos: @Sendable ([String]) -> Void
    private let onStatus: @Sendable (Status) -> Void

    public init(store: Store, containerID: String,
                onNewVideos: @escaping @Sendable ([String]) -> Void = { _ in },
                onStatus: @escaping @Sendable (Status) -> Void = { _ in }) {
        self.store = store
        self.containerID = containerID
        self.onNewVideos = onNewVideos
        self.onStatus = onStatus
    }

    public func start() async {
        guard engine == nil else { return }
        onStatus(.starting)
        let container = CKContainer(identifier: containerID)
        do {
            let account = try await container.accountStatus()
            guard account == .available else { onStatus(.noAccount); return }
        } catch {
            Self.log.error("iCloud account check failed: \(error.localizedDescription, privacy: .public)")
            onStatus(.failed(error.localizedDescription)); return
        }
        let saved = (try? await store.syncState(Self.stateKey)).flatMap {
            try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        let config = CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: saved, delegate: self)
        let engine = CKSyncEngine(config)
        self.engine = engine
        if saved == nil {
            // First run on this device (or after an account change): make the zone and send every note.
            await enqueueEverything(engine)
        }
        onStatus(.on)
        await syncNow()
    }

    /// A note was added here.
    public func saved(_ uuid: String) {
        engine?.state.add(pendingRecordZoneChanges: [.saveRecord(Self.recordID(uuid))])
    }

    /// A note was deleted here.
    public func deleted(_ uuid: String) {
        engine?.state.add(pendingRecordZoneChanges: [.deleteRecord(Self.recordID(uuid))])
    }

    /// Fetches what other devices changed and sends what's waiting. Pushes trigger this too; this
    /// covers the app coming back to the front.
    public func syncNow() async {
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch {
            Self.log.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func enqueueEverything(_ engine: CKSyncEngine) async {
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        let ids = (try? await store.allNoteUUIDs()) ?? []
        engine.state.add(pendingRecordZoneChanges: ids.map { .saveRecord(Self.recordID($0)) })
    }

    private static func recordID(_ uuid: String) -> CKRecord.ID { CKRecord.ID(recordName: uuid, zoneID: zoneID) }

    // MARK: CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            let data = try? JSONEncoder().encode(update.stateSerialization)
            try? await store.setSyncState(Self.stateKey, data)

        case .accountChange(let change):
            switch change.changeType {
            case .signIn, .switchAccounts:
                // Notes stay on the device; send them all to the account now signed in.
                await enqueueEverything(syncEngine)
                onStatus(.on)
            case .signOut:
                onStatus(.noAccount)
            @unknown default: break
            }

        case .fetchedRecordZoneChanges(let changes):
            let notes = changes.modifications.compactMap { Self.note(from: $0.record) }
            let deleted = changes.deletions.map(\.recordID.recordName)
            guard !notes.isEmpty || !deleted.isEmpty else { return }
            do {
                let newVideos = try await store.applyRemote(notes: notes, deleted: deleted)
                if !newVideos.isEmpty { onNewVideos(newVideos) }
            } catch {
                Self.log.error("Applying synced notes failed: \(error.localizedDescription, privacy: .public)")
            }

        case .sentRecordZoneChanges(let sent):
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []
            var needsZone = false
            for failure in sent.failedRecordSaves {
                let id = failure.record.recordID
                switch failure.error.code {
                case .serverRecordChanged:
                    // Notes never change after they're made, so the copy in iCloud is already right.
                    break
                case .zoneNotFound, .userDeletedZone:
                    needsZone = true
                    retry.append(.saveRecord(id))
                case .unknownItem:
                    retry.append(.saveRecord(id))
                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
                     .operationCancelled, .requestRateLimited:
                    break // the engine retries these by itself
                default:
                    Self.log.error("Couldn't save note \(id.recordName, privacy: .public): \(failure.error.localizedDescription, privacy: .public)")
                }
            }
            if needsZone { syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))]) }
            if !retry.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: retry) }

        case .fetchedDatabaseChanges, .sentDatabaseChanges, .willFetchChanges, .willFetchRecordZoneChanges,
             .didFetchRecordZoneChanges, .didFetchChanges, .willSendChanges, .didSendChanges:
            break
        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        let saves = changes.compactMap { change -> String? in
            if case .saveRecord(let id) = change { return id.recordName } else { return nil }
        }
        let notes = (try? await store.syncedNotes(uuids: saves)) ?? [:]
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            guard let note = notes[recordID.recordName] else {
                // Deleted before it was sent; nothing to save.
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            return Self.record(for: note, id: recordID)
        }
    }

    // MARK: Records

    private static func record(for note: SyncedNote, id: CKRecord.ID) -> CKRecord {
        let r = CKRecord(recordType: "Note", recordID: id)
        r["videoId"] = note.videoId
        r["time"] = note.time
        r["text"] = note.text
        r["createdAt"] = note.createdAt
        r["videoTitle"] = note.videoTitle
        r["channelId"] = note.channelId
        r["channelTitle"] = note.channelTitle
        r["publishedAt"] = note.publishedAt
        return r
    }

    private static func note(from r: CKRecord) -> SyncedNote? {
        guard r.recordType == "Note", let videoId = r["videoId"] as? String, let text = r["text"] as? String else { return nil }
        let created = r["createdAt"] as? Date ?? r.creationDate ?? .now
        return SyncedNote(uuid: r.recordID.recordName, videoId: videoId, time: r["time"] as? Double ?? 0, text: text,
                          createdAt: created, videoTitle: r["videoTitle"] as? String ?? "",
                          channelId: r["channelId"] as? String ?? "", channelTitle: r["channelTitle"] as? String ?? "",
                          publishedAt: r["publishedAt"] as? Date ?? created)
    }
}
