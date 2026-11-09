import Testing
import Foundation
@testable import BoxtubeCore

/// The database work behind importing a YouTube account and deciding what belongs in Music mode.
@Suite("Library store")
struct StoreTests {
    func video(_ id: String, channel: String, music: Bool = false) -> Video {
        Video(id: id, channelId: channel, channelTitle: channel, title: id, publishedAt: .now, durationSeconds: 200,
              categoryId: music ? "10" : "28")
    }
    func playlist(_ id: String, _ title: String) -> YouTubeClient.AccountPlaylist {
        YouTubeClient.AccountPlaylist(id: id, title: title, isPrivate: true)
    }

    @Test func importSubscribesAndDropsStarterChannelsYouDontFollow() async throws {
        let store = try Store.inMemory()
        let starter = Seeds.channels[0].id   // Veritasium in the starter set
        let otherStarter = Seeds.channels[1].id
        try await store.subscribe(Channel(id: starter, title: "Veritasium"))
        try await store.subscribe(Channel(id: otherStarter, title: "Kurzgesagt"))
        try await store.subscribe(Channel(id: "UClocal", title: "Followed only in Boxtube"))

        try await store.importAccount(
            subscriptions: [Channel(id: otherStarter, title: "Kurzgesagt"), Channel(id: "UCnew", title: "New channel")],
            playlists: [], likedIds: [], starterIds: Set(Seeds.channels.map(\.id)))

        let subscribed = try await store.read { db in Set(try Q.subscriptions(db).map(\.channel.id)) }
        #expect(subscribed == [otherStarter, "UCnew", "UClocal"])
    }

    @Test func importDetectsMusicPlaylistsAndCountsOnlyKnownVideos() async throws {
        let store = try Store.inMemory()
        try await store.upsert(videos: [
            video("m1", channel: "a", music: true), video("m2", channel: "a", music: true), video("t1", channel: "b"),
            video("t2", channel: "b"), video("t3", channel: "b"),
        ])
        try await store.importAccount(
            subscriptions: [],
            playlists: [
                (playlist("PLmusic", "Music"), ["m1", "m2", "t1"]),
                (playlist("PLcode", "programming"), ["t2", "t3", "m1", "deleted-video"]),
            ],
            likedIds: ["m2", "t1"], starterIds: [])

        let lists = try await store.read { db in try Q.playlists(db) }
        let music = try #require(lists.first { $0.id == "PLmusic" })
        let code = try #require(lists.first { $0.id == "PLcode" })
        #expect(music.playlist.isMusic, "2 of 3 videos are in the Music category")
        #expect(!code.playlist.isMusic)
        #expect(code.count == 3, "the deleted video has no details, so it isn't counted")
        let videos = try await store.read { db in try Q.playlistVideos(db, id: "PLcode").map(\.id) }
        #expect(videos == ["t2", "t3", "m1"])
        let liked = try await store.read { db in try Q.likedIds(db) }
        #expect(liked == ["m2", "t1"])
    }

    @Test func yourShowInMusicChoiceSurvivesReimport() async throws {
        let store = try Store.inMemory()
        try await store.upsert(videos: [video("m1", channel: "a", music: true), video("m2", channel: "a", music: true)])
        let items = [(playlist("PL1", "Mix"), ["m1", "m2"])]
        try await store.importAccount(subscriptions: [], playlists: items, likedIds: [], starterIds: [])
        #expect(try await store.read { db in try Playlist.fetchOne(db, key: "PL1")?.isMusic } == true)

        try await store.setPlaylistMusic("PL1", false)
        try await store.importAccount(subscriptions: [], playlists: items, likedIds: [], starterIds: [])
        let after = try await store.read { db in try Playlist.fetchOne(db, key: "PL1") }
        #expect(after?.isMusic == false)
        #expect(after?.musicChosen == true)
    }

    @Test func reimportReplacesPlaylistItemsInYouTubesOrder() async throws {
        let store = try Store.inMemory()
        try await store.upsert(videos: ["a", "b", "c"].map { video($0, channel: "x") })
        try await store.importAccount(subscriptions: [], playlists: [(playlist("PL", "L"), ["a", "b"])], likedIds: [], starterIds: [])
        try await store.importAccount(subscriptions: [], playlists: [(playlist("PL", "L"), ["c", "a", "a"])], likedIds: [], starterIds: [])
        let ids = try await store.read { db in try Q.playlistVideos(db, id: "PL").map(\.id) }
        #expect(ids == ["c", "a"])
    }

    @Test func detectsMusicArtists() async throws {
        let store = try Store.inMemory()
        for (id, title) in [("UCtopic", "Crimson Desert - Topic"), ("UCvevo", "SomeoneVEVO"), ("UCpiano", "Piano covers"),
                            ("UCmixed", "Mostly talk"), ("UCfew", "Two songs"), ("UCchosen", "Not music for me")] {
            try await store.subscribe(Channel(id: id, title: title))
        }
        try await store.upsert(channels: [Channel(id: "UCnotfollowed", title: "Other - Topic")])
        try await store.upsert(videos:
            (1...3).map { video("p\($0)", channel: "UCpiano", music: true) }
            + (1...2).map { video("mm\($0)", channel: "UCmixed", music: true) } + (1...3).map { video("mt\($0)", channel: "UCmixed") }
            + (1...2).map { video("f\($0)", channel: "UCfew", music: true) }
            + (1...3).map { video("c\($0)", channel: "UCchosen", music: true) })
        try await store.setChannelMusic("UCchosen", false)

        let flagged = try await store.detectMusicChannels()
        #expect(flagged == 3)
        let artists = try await store.read { db in Set(try Q.subscriptions(db, music: true).map(\.channel.id)) }
        #expect(artists == ["UCtopic", "UCvevo", "UCpiano"])
        let notFollowed = try await store.read { db in try Channel.fetchOne(db, key: "UCnotfollowed")?.isMusic }
        #expect(notFollowed == false, "only channels you follow are flagged")

        #expect(try await store.detectMusicChannels() == 0, "running again changes nothing")
    }

    @Test func musicChannelsLeaveTheVideosFeed() async throws {
        let store = try Store.inMemory()
        try await store.subscribe(Channel(id: "UCtalk", title: "Talk"))
        try await store.subscribe(Channel(id: "UCband", title: "Band"))
        try await store.upsert(videos: [video("talk1", channel: "UCtalk"), video("song1", channel: "UCband", music: true)])
        try await store.setChannelMusic("UCband", true)
        let videos = try await store.read { db in try Q.feed(db).map(\.id) }
        let music = try await store.read { db in try Q.feed(db, music: true).map(\.id) }
        #expect(videos == ["talk1"])
        #expect(music == ["song1"])
    }

    @Test func notInterestedAndDontRecommendHideVideosUntilUndone() async throws {
        let store = try Store.inMemory()
        try await store.subscribe(Channel(id: "a", title: "a"))
        try await store.upsert(videos: [video("a1", channel: "a"), video("a2", channel: "a"), video("b1", channel: "b"), video("c1", channel: "c")])
        try await store.cache(list: "topic:all", videoIds: ["a1", "b1", "c1"])

        try await store.hideVideo("a1")
        try await store.hideChannel("b")

        let feed = try await store.read { db in try Q.feed(db).map(\.id) }
        let topic = try await store.read { db in try Q.cachedList(db, key: "topic:all").map(\.id) }
        #expect(Set(feed) == ["a2"])
        #expect(topic == ["c1"])
        let hidden = try await store.read { db in try Q.hidden(db) }
        #expect(hidden == Q.HiddenSets(videos: ["a1"], channels: ["b"]))

        try await store.unhideAll()
        let back = try await store.read { db in try Q.cachedList(db, key: "topic:all").map(\.id) }
        #expect(back == ["a1", "b1", "c1"])
        #expect(try await store.read { db in try Q.hidden(db) }.isEmpty)
    }

    @Test func markAsWatchedFillsProgressAndUnwatchedClearsIt() async throws {
        let store = try Store.inMemory()
        let v = video("w1", channel: "a")
        try await store.upsert(videos: [v])

        try await store.setWatched(v, true)
        let row = try await store.read { db in try Q.history(db).first }
        #expect(row?.video.id == "w1")
        #expect(row?.entry.progress == 1)
        #expect(try await store.read { db in try Q.history(db, unfinishedOnly: true) }.isEmpty)

        try await store.setWatched(v, false)
        #expect(try await store.read { db in try Q.history(db) }.isEmpty)
    }
}
