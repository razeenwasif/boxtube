import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Keyless, quota-free channel feed: https://www.youtube.com/feeds/videos.xml?channel_id=UC…
/// Gives the latest ~15 uploads with title, description, views, likes and whether each is a Short.
public enum RSSFeed {
    public struct Result: Sendable {
        public var channel: Channel
        public var videos: [Video]
    }

    public static func fetch(channelId: String, session: URLSession = .shared) async throws -> Result {
        let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)")!
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw BoxtubeError.http(status, "feed for \(channelId)") }
        return try parse(data, channelId: channelId)
    }

    public static func parse(_ data: Data, channelId: String) throws -> Result {
        let delegate = FeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw BoxtubeError.decoding("channel feed") }
        let channel = Channel(id: channelId, title: delegate.feedTitle.isEmpty ? channelId : delegate.feedTitle)
        let videos = delegate.entries.compactMap { e -> Video? in
            guard !e.videoId.isEmpty else { return nil }
            return Video(
                id: e.videoId, channelId: channelId, channelTitle: channel.title, title: e.title,
                summary: e.summary, publishedAt: e.published ?? .now, durationSeconds: nil,
                viewCount: e.views, likeCount: e.likes,
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(e.videoId)/hqdefault.jpg"),
                isShort: e.link.contains("/shorts/")
            )
        }
        return Result(channel: channel, videos: videos)
    }
}

private final class FeedDelegate: NSObject, XMLParserDelegate {
    struct Entry {
        var videoId = "", title = "", summary = "", link = ""
        var published: Date?
        var views: Int?, likes: Int?
    }

    var feedTitle = ""
    var entries: [Entry] = []
    private var current: Entry?
    private var text = ""
    private var inAuthor = false
    private let iso = ISO8601DateFormatter()

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "entry": current = Entry()
        case "author": inAuthor = true
        case "link":
            if current != nil, attributes["rel"] == "alternate" { current?.link = attributes["href"] ?? "" }
        case "media:statistics": current?.views = attributes["views"].flatMap(Int.init)
        case "media:starRating": current?.likes = attributes["count"].flatMap(Int.init)
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "entry":
            if let current { entries.append(current) }
            current = nil
        case "author": inAuthor = false
        case "name":
            if current == nil, inAuthor, feedTitle.isEmpty { feedTitle = value }
        case "title":
            if current != nil { current?.title = value } else if feedTitle.isEmpty { feedTitle = value }
        case "yt:videoId": current?.videoId = value
        case "published": if current != nil { current?.published = iso.date(from: value) }
        case "media:description": current?.summary = value
        default: break
        }
        text = ""
    }
}
