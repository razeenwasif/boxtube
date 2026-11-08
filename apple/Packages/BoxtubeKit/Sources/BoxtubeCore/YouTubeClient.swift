import Foundation

public enum BoxtubeError: LocalizedError, Sendable {
    case missingAPIKey
    case http(Int, String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add a YouTube Data API key to search and load durations."
        case .http(let code, let message): "YouTube returned \(code): \(message)"
        case .decoding(let what): "Couldn't read \(what)."
        }
    }
}

/// YouTube Data API v3. Every call is cheap except `search` (100 units), which only runs when the user types.
public actor YouTubeClient {
    private let apiKey: String?
    private let session: URLSession
    private let base = URL(string: "https://www.googleapis.com/youtube/v3/")!

    public nonisolated let hasKey: Bool

    public init(apiKey: String?, session: URLSession = .shared) {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = (trimmed?.isEmpty == false && trimmed != "paste-your-key-here" && trimmed?.hasPrefix("$(") == false) ? trimmed : nil
        self.apiKey = usable
        self.hasKey = usable != nil
        self.session = session
    }

    // MARK: Endpoints

    public func videos(ids: [String]) async throws -> [Video] {
        var result: [Video] = []
        for chunk in ids.uniqued().chunked(50) {
            let page: Page<VideoResource> = try await get("videos", [
                "part": "snippet,contentDetails,statistics,liveStreamingDetails",
                "id": chunk.joined(separator: ","),
                "maxResults": "50",
            ])
            result += page.items.map(\.video)
        }
        return result
    }

    public func popular(categoryId: String? = nil, regionCode: String = Locale.current.region?.identifier ?? "US") async throws -> [Video] {
        var query = ["part": "snippet,contentDetails,statistics", "chart": "mostPopular", "maxResults": "40", "regionCode": regionCode]
        if let categoryId { query["videoCategoryId"] = categoryId }
        let page: Page<VideoResource> = try await get("videos", query)
        return page.items.map(\.video)
    }

    public func search(_ text: String, duration: String? = nil) async throws -> [Video] {
        var query = ["part": "snippet", "q": text, "type": "video", "maxResults": "25", "safeSearch": "moderate"]
        if let duration { query["videoDuration"] = duration }
        let page: Page<SearchResource> = try await get("search", query)
        let ids = page.items.compactMap(\.id.videoId)
        let details = try await videos(ids: ids)
        let byId = Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })
        return ids.compactMap { byId[$0] }
    }

    public func searchChannels(_ text: String) async throws -> [Channel] {
        let page: Page<SearchResource> = try await get("search", ["part": "snippet", "q": text, "type": "channel", "maxResults": "10"])
        let ids = page.items.compactMap(\.id.channelId)
        return try await channels(ids: ids)
    }

    public func channels(ids: [String]) async throws -> [Channel] {
        var result: [Channel] = []
        for chunk in ids.uniqued().chunked(50) {
            let page: Page<ChannelResource> = try await get("channels", ["part": "snippet,statistics", "id": chunk.joined(separator: ",")])
            result += page.items.map(\.channel)
        }
        return result
    }

    public struct TopComment: Sendable, Hashable {
        public var author: String
        public var text: String
        public var likes: Int
        public var total: Int?
    }

    /// The most relevant comment plus the video's comment count (2 units).
    public func topComment(videoId: String) async throws -> TopComment? {
        let page: Page<CommentThreadResource> = try await get("commentThreads", ["part": "snippet", "videoId": videoId, "order": "relevance", "maxResults": "1", "textFormat": "plainText"])
        guard let c = page.items.first?.snippet.topLevelComment.snippet else { return nil }
        let stats: Page<VideoStatsOnly> = try await get("videos", ["part": "statistics", "id": videoId])
        return TopComment(author: c.authorDisplayName, text: c.textDisplay, likes: c.likeCount ?? 0, total: stats.items.first?.statistics.commentCount.flatMap(Int.init))
    }

    /// Shorts uploaded by a channel live in the hidden `UUSH…` playlist.
    public func shortsIds(channelId: String) async throws -> [String] {
        guard channelId.hasPrefix("UC") else { return [] }
        let playlist = "UUSH" + channelId.dropFirst(2)
        let page: Page<PlaylistItemResource> = try await get("playlistItems", ["part": "contentDetails", "playlistId": String(playlist), "maxResults": "15"])
        return page.items.map(\.contentDetails.videoId)
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        guard let apiKey else { throw BoxtubeError.missingAPIKey }
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } + [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        if let bundle = Bundle.main.bundleIdentifier { request.setValue(bundle, forHTTPHeaderField: "X-Ios-Bundle-Identifier") }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message ?? "request failed"
            throw BoxtubeError.http(status, message)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw BoxtubeError.decoding(path)
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Wire types

private struct APIErrorEnvelope: Decodable { struct E: Decodable { var message: String }; var error: E }
private struct Page<Item: Decodable>: Decodable { var items: [Item] }

private struct Thumbs: Decodable {
    struct T: Decodable { var url: URL }
    var `default`: T?; var medium: T?; var high: T?; var standard: T?; var maxres: T?
    var best: URL? { (maxres ?? standard ?? high ?? medium ?? `default`)?.url }
    var avatar: URL? { (high ?? medium ?? `default`)?.url }
}

private struct VideoResource: Decodable {
    struct Snippet: Decodable {
        var channelId: String; var channelTitle: String; var title: String; var description: String
        var publishedAt: Date; var thumbnails: Thumbs; var categoryId: String?; var liveBroadcastContent: String?
    }
    struct Details: Decodable { var duration: String? }
    struct Stats: Decodable { var viewCount: String?; var likeCount: String? }
    var id: String; var snippet: Snippet; var contentDetails: Details?; var statistics: Stats?

    var video: Video {
        let seconds = contentDetails?.duration.flatMap(ISODuration.seconds)
        return Video(
            id: id, channelId: snippet.channelId, channelTitle: snippet.channelTitle, title: snippet.title,
            summary: snippet.description, publishedAt: snippet.publishedAt, durationSeconds: seconds,
            viewCount: statistics?.viewCount.flatMap(Int.init), likeCount: statistics?.likeCount.flatMap(Int.init),
            thumbnailURL: snippet.thumbnails.best, isShort: (seconds ?? 999) <= 60,
            isLive: snippet.liveBroadcastContent == "live", categoryId: snippet.categoryId
        )
    }
}

private struct SearchResource: Decodable {
    struct ID: Decodable { var videoId: String?; var channelId: String? }
    var id: ID
}

private struct ChannelResource: Decodable {
    struct Snippet: Decodable { var title: String; var thumbnails: Thumbs }
    struct Stats: Decodable { var subscriberCount: String? }
    var id: String; var snippet: Snippet; var statistics: Stats?
    var channel: Channel {
        Channel(id: id, title: snippet.title, avatarURL: snippet.thumbnails.avatar,
                subscriberCount: statistics?.subscriberCount.flatMap(Int.init))
    }
}

private struct CommentThreadResource: Decodable {
    struct Snippet: Decodable { var topLevelComment: Top }
    struct Top: Decodable { var snippet: Inner }
    struct Inner: Decodable { var authorDisplayName: String; var textDisplay: String; var likeCount: Int? }
    var snippet: Snippet
}

private struct VideoStatsOnly: Decodable {
    struct Stats: Decodable { var commentCount: String? }
    var statistics: Stats
}

private struct PlaylistItemResource: Decodable {
    struct Details: Decodable { var videoId: String }
    var contentDetails: Details
}

// MARK: - Helpers

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
