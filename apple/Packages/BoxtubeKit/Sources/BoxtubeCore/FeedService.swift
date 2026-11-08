import Foundation
import GRDB

/// Pulls fresh data into the Store. Subscriptions use free RSS; the API key (if any) only fills in
/// durations, avatars, topics and search.
public actor FeedService {
    public let store: Store
    public let client: YouTubeClient
    private var inFlight = false

    public init(store: Store, client: YouTubeClient) {
        self.store = store
        self.client = client
    }

    public struct Report: Sendable {
        public var channels = 0
        public var videos = 0
        public var failures = 0
    }

    // MARK: Subscriptions (RSS, no quota)

    @discardableResult
    public func refreshSubscriptions(force: Bool = false, maxAge: TimeInterval = 15 * 60) async -> Report {
        guard !inFlight else { return Report() }
        inFlight = true
        defer { inFlight = false }

        let channels = (try? await store.read { db in
            try Channel.filter(Column("isSubscribed") == true).fetchAll(db)
        }) ?? []
        let due = channels.filter { force || ($0.lastFetchedAt.map { Date.now.timeIntervalSince($0) > maxAge } ?? true) }
        var report = Report()

        await withTaskGroup(of: RSSFeed.Result?.self) { group in
            var iterator = due.makeIterator()
            func addNext() {
                guard let channel = iterator.next() else { return }
                group.addTask { try? await RSSFeed.fetch(channelId: channel.id) }
            }
            for _ in 0..<6 { addNext() }
            while let result = await group.next() {
                if let result {
                    try? await store.upsert(channels: [result.channel])
                    try? await store.upsert(videos: result.videos)
                    try? await store.setFetched(channelId: result.channel.id)
                    report.channels += 1
                    report.videos += result.videos.count
                } else {
                    report.failures += 1
                }
                addNext()
            }
        }

        if client.hasKey {
            await enrichMissingDetails()
            await enrichChannels()
        }
        return report
    }

    /// Fills durations / categories for recent videos that came from RSS (1 unit per 50 videos).
    public func enrichMissingDetails(limit: Int = 200) async {
        guard client.hasKey else { return }
        let ids = (try? await store.read { db in
            try String.fetchAll(db, sql: """
                SELECT id FROM video WHERE durationSeconds IS NULL OR categoryId IS NULL
                ORDER BY publishedAt DESC LIMIT ?
                """, arguments: [limit])
        }) ?? []
        guard !ids.isEmpty, let details = try? await client.videos(ids: ids) else { return }
        try? await store.upsert(videos: details)
    }

    public func enrich(videoIds: [String]) async {
        guard client.hasKey, !videoIds.isEmpty, let details = try? await client.videos(ids: videoIds) else { return }
        try? await store.upsert(videos: details)
    }

    private func enrichChannels() async {
        let ids = (try? await store.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM channel WHERE avatarURL IS NULL LIMIT 50")
        }) ?? []
        guard !ids.isEmpty, let channels = try? await client.channels(ids: ids) else { return }
        try? await store.upsert(channels: channels)
    }

    // MARK: Topics & search (API key)

    public func loadTopic(_ topic: Topic, maxAge: TimeInterval = 30 * 60) async throws {
        guard client.hasKey else { throw BoxtubeError.missingAPIKey }
        let key = "topic:\(topic.id)"
        if let age = try await store.read({ db in try Q.cacheAge(db, key: key) }), Date.now.timeIntervalSince(age) < maxAge { return }
        let videos: [Video]
        if let query = topic.query, topic.categoryId == nil || topic.id == "coding" || topic.id == "science" {
            videos = try await client.search(query)
        } else {
            videos = try await client.popular(categoryId: topic.categoryId)
        }
        try await store.upsert(videos: videos)
        try await store.cache(list: key, videoIds: videos.map(\.id))
    }

    public func search(_ text: String) async throws -> [Video] {
        let videos = try await client.search(text)
        try await store.upsert(videos: videos)
        try await store.cache(list: "search", videoIds: videos.map(\.id))
        return videos
    }

    public func searchChannels(_ text: String) async throws -> [Channel] {
        let channels = try await client.searchChannels(text)
        try await store.upsert(channels: channels)
        return channels
    }

    /// Opens a video that may not be in the store yet (deep link, pasted URL).
    public func ensureVideo(_ id: String) async -> Video? {
        if let existing = try? await store.read({ db in try Q.video(db, id) }) { return existing }
        if client.hasKey, let fetched = try? await client.videos(ids: [id]).first {
            try? await store.upsert(videos: [fetched])
            return fetched
        }
        return nil
    }

    public func topComment(videoId: String) async -> YouTubeClient.TopComment? {
        guard client.hasKey else { return nil }
        return try? await client.topComment(videoId: videoId)
    }

    // MARK: Your YouTube account

    public struct ImportReport: Sendable {
        public var subscriptions = 0
        public var playlists = 0
        public var liked = 0
    }

    /// Copies subscriptions, playlists and liked videos from YouTube into the library (about 10–30 quota units).
    public func importAccount(token: String) async throws -> ImportReport {
        async let subsTask = client.mySubscriptions(token: token)
        async let listsTask = client.myPlaylists(token: token)
        async let likedTask = client.myLikedVideos(token: token)
        let (subs, lists, liked) = try await (subsTask, listsTask, likedTask)

        var playlistItems: [(YouTubeClient.AccountPlaylist, [String])] = []
        for list in lists {
            let ids = (try? await client.playlistVideoIds(list.id, token: token)) ?? []
            playlistItems.append((list, ids))
        }
        // Playlist rows only show videos the store knows about.
        let known = Set((try? await store.read { db in try String.fetchAll(db, sql: "SELECT id FROM video") }) ?? [])
        let missing = playlistItems.flatMap(\.1).filter { !known.contains($0) }
        let details = (try? await client.videos(ids: missing, token: token)) ?? []

        try await store.upsert(videos: liked + details)
        try await store.importAccount(subscriptions: subs, playlists: playlistItems, likedIds: liked.map(\.id),
                                      starterIds: Set(Seeds.channels.map(\.id)))
        return ImportReport(subscriptions: subs.count, playlists: lists.count, liked: liked.count)
    }

    // MARK: First launch

    public func seedIfNeeded() async {
        let count = (try? await store.read { db in try Channel.fetchCount(db) }) ?? 0
        guard count == 0 else { return }
        for seed in Seeds.channels {
            try? await store.subscribe(Channel(id: seed.id, title: seed.title, isMusic: seed.music), music: seed.music)
        }
        if let later = try? await store.createPlaylist(title: "Late night focus", music: true) { _ = later }
        _ = try? await store.createPlaylist(title: "Weekend projects")
    }
}

public enum Seeds {
    public struct SeedChannel: Sendable { public var id: String; public var title: String; public var music: Bool }
    /// A starter set so the app isn't empty before you add your own subscriptions.
    public static let channels: [SeedChannel] = [
        .init(id: "UCHnyfMqiRRG1u-2MsSQLbXA", title: "Veritasium", music: false),
        .init(id: "UCsXVk37bltHxD1rDPwtNM8Q", title: "Kurzgesagt", music: false),
        .init(id: "UCsBjURrPoezykLs9EqgamOA", title: "Fireship", music: false),
        .init(id: "UCYO_jab_esuFRV4b17AJtAw", title: "3Blue1Brown", music: false),
        .init(id: "UCBJycsmduvYEL83R_InASjA", title: "Marques Brownlee", music: false),
        .init(id: "UC9-y-6csu5WGm29I7JiwpnA", title: "Computerphile", music: false),
        .init(id: "UCY1kMZp36IQSyNx_9h4mpCg", title: "Mark Rober", music: false),
        .init(id: "UCBa659QWEk1AI4Tg--mrJ2A", title: "Tom Scott", music: false),
        .init(id: "UCSJ4gkVC6NrvII8umztf0Ow", title: "Lofi Girl", music: true),
        .init(id: "UC4eYXhJI4-7wBWc8UNRwD4A", title: "NPR Music", music: true),
    ]
}
