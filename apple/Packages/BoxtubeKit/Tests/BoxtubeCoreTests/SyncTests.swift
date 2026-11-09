import Testing
import Foundation
@testable import BoxtubeCore

/// Plays YouTube's part: records every call and can refuse on cue.
actor FakeYouTube: YouTubeWriter {
    var calls: [String] = []
    /// Call number (1-based) → the error to throw on that call.
    var failures: [Int: Error] = [:]
    var newPlaylistId = "PLnew"
    var subscriptionIds: [String: String] = [:]

    func failing(_ n: Int, with error: Error) { failures[n] = error }
    func setSubscription(_ channel: String, _ id: String) { subscriptionIds[channel] = id }

    private func record(_ call: String) throws {
        calls.append(call)
        if let e = failures[calls.count] { throw e }
    }
    func rate(videoId: String, rating: String, token: String) async throws { try record("rate \(videoId) \(rating)") }
    func subscribe(channelId: String, token: String) async throws { try record("subscribe \(channelId)") }
    func subscriptionId(channelId: String, token: String) async throws -> String? {
        try record("find subscription \(channelId)"); return subscriptionIds[channelId]
    }
    func deleteSubscription(id: String, token: String) async throws { try record("unsubscribe \(id)") }
    func addToPlaylist(playlistId: String, videoId: String, token: String) async throws { try record("add \(videoId) to \(playlistId)") }
    func playlistItemIds(playlistId: String, videoId: String, token: String) async throws -> [String] {
        try record("find \(videoId) in \(playlistId)"); return ["item-\(videoId)"]
    }
    func deletePlaylistItem(id: String, token: String) async throws { try record("delete \(id)") }
    func createPlaylist(title: String, token: String) async throws -> String { try record("create \(title)"); return newPlaylistId }
    func deletePlaylist(id: String, token: String) async throws { try record("delete playlist \(id)") }
}

@Suite("Two-way sync")
struct SyncTests {
    func waiting(_ store: Store) async throws -> [String] {
        try await store.read { db in try OutboxOp.order(Column("id")).fetchAll(db).map { "\($0.kind.rawValue) \($0.target)\($0.playlistId.map { " " + $0 } ?? "")" } }
    }

    @Test func newerChangesReplaceOlderOnesForTheSameThing() async throws {
        let store = try Store.inMemory()
        try await store.enqueue(.like, target: "v1")
        try await store.enqueue(.unrate, target: "v1")
        try await store.enqueue(.subscribe, target: "UC1")
        try await store.enqueue(.unsubscribe, target: "UC1")
        try await store.enqueue(.playlistAdd, target: "v2", playlistId: "PLa")
        try await store.enqueue(.playlistAdd, target: "v2", playlistId: "PLb")
        try await store.enqueue(.playlistRemove, target: "v2", playlistId: "PLa")
        try await store.enqueue(.like, target: "v3")
        #expect(try await waiting(store) == ["unrate v1", "unsubscribe UC1", "playlistAdd v2 PLb", "playlistRemove v2 PLa", "like v3"])
    }

    @Test func sendsInOrderAndEmptiesTheOutbox() async throws {
        let store = try Store.inMemory()
        let youtube = FakeYouTube()
        await youtube.setSubscription("UCgone", "SUB1")
        try await store.enqueue(.like, target: "v1")
        try await store.enqueue(.dislike, target: "v2")
        try await store.enqueue(.subscribe, target: "UCnew")
        try await store.enqueue(.unsubscribe, target: "UCgone")
        try await store.enqueue(.playlistRemove, target: "v3", playlistId: "PLx")

        let report = await SyncService(store: store, youtube: youtube).flush(token: "t")
        #expect(report == SyncService.Report(sent: 5, dropped: 0, stoppedBy: nil))
        #expect(await youtube.calls == [
            "rate v1 like", "rate v2 dislike", "subscribe UCnew", "find subscription UCgone", "unsubscribe SUB1",
            "find v3 in PLx", "delete item-v3",
        ])
        #expect(try await waiting(store).isEmpty)
    }

    @Test func aNewPlaylistTakesYouTubesIdAndItsQueuedAdditionsFollow() async throws {
        let store = try Store.inMemory()
        try await store.upsert(videos: [Video(id: "v1", channelId: "c", channelTitle: "C", title: "v1", publishedAt: .now)])
        let local = try await store.createPlaylist(title: "Road trip")
        try await store.add(videoId: "v1", toPlaylist: local.id)
        try await store.enqueue(.playlistCreate, target: local.id)
        try await store.enqueue(.playlistAdd, target: "v1", playlistId: local.id)

        let youtube = FakeYouTube()
        _ = await SyncService(store: store, youtube: youtube).flush(token: "t")
        #expect(await youtube.calls == ["create Road trip", "add v1 to PLnew"])
        let lists = try await store.read { db in try Playlist.fetchAll(db).map(\.id) }
        #expect(lists == ["PLnew"])
        let items = try await store.read { db in try Q.playlistVideos(db, id: "PLnew").map(\.id) }
        #expect(items == ["v1"])
    }

    @Test func editsToBoxtubeOnlyPlaylistsStayLocal() async throws {
        let store = try Store.inMemory()
        try await store.enqueue(.playlistAdd, target: "v1", playlistId: UUID().uuidString)
        let youtube = FakeYouTube()
        let report = await SyncService(store: store, youtube: youtube).flush(token: "t")
        #expect(await youtube.calls.isEmpty)
        #expect(report.sent == 1)
        #expect(try await waiting(store).isEmpty)
    }

    @Test func runningOutOfQuotaStopsAndKeepsTheRest() async throws {
        let store = try Store.inMemory()
        let youtube = FakeYouTube()
        await youtube.failing(2, with: BoxtubeError.youtube(status: 403, reason: "quotaExceeded", message: "quota"))
        for v in ["v1", "v2", "v3"] { try await store.enqueue(.like, target: v) }
        let report = await SyncService(store: store, youtube: youtube).flush(token: "t")
        #expect(report.sent == 1)
        #expect(report.stoppedBy == .quota)
        #expect(try await waiting(store) == ["like v2", "like v3"])
    }

    @Test func alreadyDoneOnYouTubeCountsAsSent() async throws {
        let store = try Store.inMemory()
        let youtube = FakeYouTube()
        await youtube.failing(1, with: BoxtubeError.youtube(status: 400, reason: "subscriptionDuplicate", message: "dup"))
        await youtube.failing(2, with: BoxtubeError.youtube(status: 404, reason: "videoNotFound", message: "gone"))
        try await store.enqueue(.subscribe, target: "UC1")
        try await store.enqueue(.like, target: "deleted")
        let report = await SyncService(store: store, youtube: youtube).flush(token: "t")
        #expect(report.sent == 1)
        #expect(report.dropped == 1)
        #expect(try await waiting(store).isEmpty)
    }

    @Test func aChangeYouTubeKeepsRefusingIsSetAside() async throws {
        let store = try Store.inMemory()
        try await store.enqueue(.like, target: "bad")
        try await store.enqueue(.like, target: "good")
        let youtube = FakeYouTube()
        for n in [1, 3, 4] { await youtube.failing(n, with: BoxtubeError.youtube(status: 400, reason: "invalidValue", message: "Bad request")) }
        let service = SyncService(store: store, youtube: youtube)
        // Run 1: the bad one is refused and waits; the good one still goes. Runs 2 and 3: one retry each.
        _ = await service.flush(token: "t")
        #expect(await youtube.calls == ["rate bad like", "rate good like"])
        _ = await service.flush(token: "t")
        _ = await service.flush(token: "t")
        #expect(await youtube.calls.count == 4, "never retried twice in one run")
        let summary = try await store.read { db in try Q.outboxSummary(db) }
        #expect(summary == Q.OutboxSummary(waiting: 0, failed: 1, lastError: "Bad request"))
        _ = await service.flush(token: "t")
        #expect(await youtube.calls.count == 4, "set aside after three refusals")
        try await store.clearFailedOutbox()
        #expect(try await waiting(store).isEmpty)
    }

    @Test func noConnectionStopsWithoutCountingAFailure() async throws {
        let store = try Store.inMemory()
        let youtube = FakeYouTube()
        await youtube.failing(1, with: URLError(.notConnectedToInternet))
        try await store.enqueue(.like, target: "v1")
        let report = await SyncService(store: store, youtube: youtube).flush(token: "t")
        #expect(report.stoppedBy == .unreachable)
        let op = try await store.read { db in try OutboxOp.fetchOne(db) }
        #expect(op?.attempts == 0)
    }

    @Test func importMirrorsYouTubeButKeepsChangesStillOnTheirWay() async throws {
        let store = try Store.inMemory()
        for id in ["UCkept", "UCleftOnYouTube", "UCjustFollowed"] { try await store.subscribe(Channel(id: id, title: id)) }
        try await store.upsert(videos: ["v1", "v2"].map { Video(id: $0, channelId: "c", channelTitle: "C", title: $0, publishedAt: .now) })
        try await store.enqueue(.subscribe, target: "UCjustFollowed")
        try await store.enqueue(.unrate, target: "v1")
        try await store.enqueue(.playlistAdd, target: "v2", playlistId: "PL1")

        try await store.importAccount(
            subscriptions: [Channel(id: "UCkept", title: "UCkept")],
            playlists: [(YouTubeClient.AccountPlaylist(id: "PL1", title: "List", isPrivate: true), ["v1"])],
            likedIds: ["v1"], starterIds: [], mirrorSubscriptions: true)

        let subscribed = try await store.read { db in Set(try Q.subscriptions(db).map(\.channel.id)) }
        #expect(subscribed == ["UCkept", "UCjustFollowed"])
        #expect(try await store.read { db in try Q.likedIds(db) }.isEmpty, "the unlike on its way wins over YouTube's old like")
        let items = try await store.read { db in try Q.playlistVideos(db, id: "PL1").map(\.id) }
        #expect(items == ["v1", "v2"])
    }

    @Test func withoutSyncImportLeavesLocalSubscriptionsAlone() async throws {
        let store = try Store.inMemory()
        try await store.subscribe(Channel(id: "UClocal", title: "Local"))
        try await store.importAccount(subscriptions: [], playlists: [], likedIds: [], starterIds: [])
        let subscribed = try await store.read { db in try Q.subscriptions(db).map(\.channel.id) }
        #expect(subscribed == ["UClocal"])
    }

    // MARK: Deleting and publishing playlists

    func remotePlaylist(_ store: Store, _ id: String, videos: [String]) async throws {
        try await store.upsert(videos: videos.map { Video(id: $0, channelId: "c", channelTitle: "C", title: $0, publishedAt: .now) })
        try await store.importAccount(subscriptions: [], playlists: [(YouTubeClient.AccountPlaylist(id: id, title: "Mix", isPrivate: true), videos)],
                                      likedIds: [], starterIds: [])
    }

    @Test func deletingOnYouTubeQueuesOneDeleteAndDropsItsEdits() async throws {
        let store = try Store.inMemory()
        try await remotePlaylist(store, "PL1", videos: ["v1"])
        try await store.enqueue(.playlistAdd, target: "v2", playlistId: "PL1")
        try await store.deletePlaylist("PL1", onYouTube: true)
        #expect(try await waiting(store) == ["playlistDelete PL1"])
        let youtube = FakeYouTube()
        _ = await SyncService(store: store, youtube: youtube).flush(token: "t")
        #expect(await youtube.calls == ["delete playlist PL1"])
        // YouTube still lists it until the delete lands; the import mustn't bring it back meanwhile.
        try await remotePlaylist(store, "PL1", videos: ["v1"])
        #expect(try await store.read { db in try Playlist.fetchOne(db, key: "PL1") } == nil)
    }

    @Test func removingFromBoxtubeOnlyStaysRemovedUntilYouBringItBack() async throws {
        let store = try Store.inMemory()
        try await remotePlaylist(store, "PL1", videos: ["v1"])
        try await store.deletePlaylist("PL1", onYouTube: false)
        #expect(try await waiting(store).isEmpty, "nothing goes to YouTube")
        try await remotePlaylist(store, "PL1", videos: ["v1"])
        #expect(try await store.read { db in try Playlist.fetchOne(db, key: "PL1") } == nil)
        #expect(try await store.read { db in try Q.hiddenPlaylistCount(db) } == 1)

        try await store.unhidePlaylists()
        try await remotePlaylist(store, "PL1", videos: ["v1"])
        #expect(try await store.read { db in try Playlist.fetchOne(db, key: "PL1")?.title } == "Mix")
    }

    @Test func deletingAPlaylistThatNeverReachedYouTubeLeavesNoTrace() async throws {
        let store = try Store.inMemory()
        let local = try await store.createPlaylist(title: "Draft")
        try await store.enqueue(.playlistCreate, target: local.id)
        try await store.enqueue(.playlistAdd, target: "v1", playlistId: local.id)
        try await store.deletePlaylist(local.id, onYouTube: true)
        #expect(try await waiting(store).isEmpty)
        #expect(try await store.read { db in try Q.hiddenPlaylistCount(db) } == 0)
    }

    @Test func publishingSendsThePlaylistThenItsVideosInOrder() async throws {
        let store = try Store.inMemory()
        try await store.upsert(videos: ["a", "b"].map { Video(id: $0, channelId: "c", channelTitle: "C", title: $0, publishedAt: .now) })
        let local = try await store.createPlaylist(title: "Weekend projects")
        try await store.add(videoId: "a", toPlaylist: local.id)
        try await store.add(videoId: "b", toPlaylist: local.id)

        #expect(try await store.publishPlaylist(local.id) == 2)
        #expect(try await store.publishPlaylist(local.id) == 0, "already on its way")
        #expect(try await store.read { db in try Q.publishingPlaylists(db) } == [local.id])

        let youtube = FakeYouTube()
        _ = await SyncService(store: store, youtube: youtube).flush(token: "t")
        #expect(await youtube.calls == ["create Weekend projects", "add a to PLnew", "add b to PLnew"])
        #expect(try await store.read { db in try Q.playlistVideos(db, id: "PLnew").map(\.id) } == ["a", "b"])
        #expect(try await store.publishPlaylist("PLnew") == 0, "YouTube playlists can't be published again")
    }
}
