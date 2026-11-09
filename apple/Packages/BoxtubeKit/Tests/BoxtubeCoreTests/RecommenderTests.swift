import Testing
import Foundation
@testable import BoxtubeCore

/// Boxtube's on-device recommendations: what they learn from, and how they mix.
@Suite("Recommendations")
struct RecommenderTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func video(_ id: String, _ channel: String, _ title: String, daysAgo: Double = 1, minutes: Int = 15,
               views: Int? = nil, category: String = "28") -> Video {
        Video(id: id, channelId: channel, channelTitle: channel.uppercased(), title: title,
              publishedAt: now.addingTimeInterval(-daysAgo * 86_400), durationSeconds: minutes * 60, viewCount: views, categoryId: category)
    }

    func event(_ v: Video, _ kind: Recommender.Event.Kind, daysAgo: Double = 1) -> Recommender.Event {
        .init(video: v, kind: kind, at: now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test func channelsYouFinishRankAboveOnesYouAbandon() {
        let finished = (0..<3).map { video("f\($0)", "loved", "Building a compiler part \($0)") }
        let abandoned = (0..<3).map { video("a\($0)", "skipped", "Celebrity drama recap \($0)") }
        let candidates = [video("c1", "skipped", "Another celebrity drama recap"), video("c2", "loved", "Writing a parser by hand")]
        let input = Recommender.Input(candidates: candidates,
                                      events: finished.map { event($0, .finished) } + abandoned.map { event($0, .abandoned) },
                                      subscribed: ["loved", "skipped"])
        let ranked = Recommender.rank(input, now: now)
        #expect(ranked.first?.video.id == "c2")
        #expect(ranked.first?.reason == "You often finish LOVED's videos")
    }

    @Test func titleWordsYouLikeCarryAcrossChannels() {
        let liked = video("l1", "other", "Rust ownership explained")
        let candidates = [video("c1", "x", "Gardening for beginners"), video("c2", "y", "Rust lifetimes and ownership deep dive")]
        let input = Recommender.Input(candidates: candidates, events: [event(liked, .liked)], subscribed: ["x", "y"])
        let ranked = Recommender.rank(input, now: now)
        #expect(ranked.first?.video.id == "c2")
        #expect(ranked.first?.reason == "Because you liked “Rust ownership explained”")
    }

    @Test func dislikesPushAChannelDown() {
        let disliked = video("d1", "meh", "Ten hacks you need")
        let candidates = [video("c1", "meh", "Ten more hacks you need"), video("c2", "fine", "A calm walk through Kyoto")]
        let input = Recommender.Input(candidates: candidates, events: [event(disliked, .disliked)], subscribed: ["meh", "fine"])
        #expect(Recommender.rank(input, now: now).first?.video.id == "c2")
    }

    @Test func newerWinsWhenNothingElseDiffers() {
        let candidates = [video("old", "a", "Weekly update", daysAgo: 20), video("new", "b", "Weekly update", daysAgo: 0.5)]
        let input = Recommender.Input(candidates: candidates, events: [], subscribed: ["a", "b"])
        #expect(Recommender.rank(input, now: now).first?.video.id == "new")
    }

    @Test func oneChannelDoesNotTakeOverTheTop() {
        let loved = (0..<4).map { video("f\($0)", "loved", "Episode \($0) of the show") }
        let many = (0..<10).map { video("m\($0)", "loved", "Show number \($0)", daysAgo: Double($0) * 0.1) }
        let others = (0..<6).map { video("o\($0)", "other\($0)", "Different thing \($0)") }
        let input = Recommender.Input(candidates: many + others, events: loved.map { event($0, .finished) },
                                      subscribed: Set(["loved"] + (0..<6).map { "other\($0)" }))
        let top6 = Recommender.rank(input, now: now).prefix(6)
        #expect(top6.filter { $0.video.channelId == "loved" }.count <= 3)
    }

    @Test func somethingNewMakesTheFirstSix() {
        // Strong familiar picks would fill the top on score alone; the mix keeps a slot for a new channel.
        let loved = (0..<4).map { video("f\($0)", "sub\($0)", "Loved thing \($0)") }
        let familiar = (0..<12).map { video("s\($0)", "sub\($0 % 4)", "Clip \($0) about cooking pasta") }
        let unfamiliar = video("n1", "stranger", "Something unexpected", daysAgo: 6)
        let input = Recommender.Input(candidates: familiar + [unfamiliar], events: loved.map { event($0, .finished) },
                                      subscribed: ["sub0", "sub1", "sub2", "sub3"])
        let ranked = Recommender.rank(input, now: now)
        let slot = ranked.firstIndex { $0.video.id == "n1" }
        #expect(slot != nil && slot! < 6)
        #expect(ranked.first { $0.video.id == "n1" }?.reason == "Something new from STRANGER")
    }

    @Test func orderIsStableWithinADay() {
        let candidates = (0..<20).map { video("v\($0)", "c\($0 % 5)", "Same title") }
        let input = Recommender.Input(candidates: candidates, events: [], subscribed: Set((0..<5).map { "c\($0)" }))
        let first = Recommender.rank(input, now: now).map(\.id)
        let later = Recommender.rank(input, now: now.addingTimeInterval(3600)).map(\.id)
        #expect(first == later)
    }

    @Test func libraryReadLeavesOutHiddenFinishedAndDislikedVideos() async throws {
        let store = try Store.inMemory()
        try await store.subscribe(Channel(id: "a", title: "A"))
        try await store.subscribe(Channel(id: "b", title: "B"))
        let vids = ["keep", "hidden", "done", "nope"].map { video($0, "a", "Video \($0)", daysAgo: 0) }
            + [video("blocked", "b", "Video blocked", daysAgo: 0)]
        try await store.upsert(videos: vids)
        try await store.hideVideo("hidden")
        try await store.hideChannel("b")
        try await store.setWatched(vids[2], true)
        try await store.setDisliked("nope", true)

        let ids = try await store.read { db in try Q.recommendations(db, now: .now).map(\.id) }
        #expect(ids == ["keep"])
    }

    @Test func channelsYouDontFollowGetAShareOfTheTop() {
        let watched = (0..<6).map { video("w\($0)", "sub\($0 % 3)", "Home espresso machine review \($0)") }
        let following = (0..<12).map { video("s\($0)", "sub\($0 % 3)", "Espresso tips number \($0)") }
        let outside = (0..<4).map { video("o\($0)", "out\($0)", "Espresso grinder showdown \($0)", daysAgo: 3) }
        let input = Recommender.Input(candidates: following + outside, events: watched.map { event($0, .finished) },
                                      subscribed: ["sub0", "sub1", "sub2"])
        let top6 = Recommender.rank(input, now: now).prefix(6)
        #expect(top6.filter { $0.video.channelId.hasPrefix("out") }.count >= 2)
    }

    @Test func interestsPairDistinctiveWordsAndSkipChannelNames() {
        let watched = [
            video("a", "mkbhd", "Mechanical keyboard switches explained"),
            video("b", "mkbhd", "Building a mechanical keyboard from scratch"),
            video("c", "other", "Mechanical keyboard sound test"),
            video("d", "other", "Pasta from scratch"),
        ]
        let input = Recommender.Input(candidates: [video("x", "z", "Something else")],
                                      events: watched.map { event($0, .finished) }, subscribed: [])
        let interests = Recommender.interests(input, now: now, count: 1)
        #expect(interests.queries == ["keyboard mechanical"] || interests.queries == ["mechanical keyboard"])
        #expect(!interests.queries.joined().contains("mkbhd"))
        #expect(interests.categories == ["28"])
    }

    @Test func discoveredListsCountOnlyWhenAllowed() async throws {
        let store = try Store.inMemory()
        try await store.subscribe(Channel(id: "a", title: "A"))
        try await store.upsert(videos: [video("mine", "a", "From a channel I follow", daysAgo: 0),
                                        video("found", "elsewhere", "Found by a search", daysAgo: 90)])
        try await store.cache(list: "rec:search:something", videoIds: ["found"])

        let open = try await store.read { db in Set(try Q.recommendations(db, now: .now, includeUnfollowed: true).map(\.id)) }
        let closed = try await store.read { db in Set(try Q.recommendations(db, now: .now, includeUnfollowed: false).map(\.id)) }
        #expect(open == ["mine", "found"])
        #expect(closed == ["mine"])
    }
}
