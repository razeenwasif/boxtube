import Testing
import Foundation
@testable import BoxtubeCore

@Suite("Channel feeds")
struct RSSTests {
    let xml = """
    <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
    <title>Veritasium</title><author><name>Veritasium</name></author>
    <entry><yt:videoId>v1</yt:videoId><title>Quantum &amp; you</title>
    <link rel="alternate" href="https://www.youtube.com/watch?v=v1"/>
    <published>2026-11-05T10:00:00+00:00</published>
    <media:group><media:description>0:00 Start
    1:59 Race</media:description></media:group></entry>
    <entry><yt:videoId>v2</yt:videoId><title>Short one</title>
    <link rel="alternate" href="https://www.youtube.com/shorts/v2"/>
    <published>2026-11-06T10:00:00+00:00</published></entry>
    <entry><title>No id, skipped</title></entry>
    </feed>
    """

    @Test func parsesEntriesInOrder() throws {
        let result = try RSSFeed.parse(Data(xml.utf8), channelId: "UCHnyfMqiRRG1u-2MsSQLbXA")
        #expect(result.channel.id == "UCHnyfMqiRRG1u-2MsSQLbXA")
        #expect(result.channel.title == "Veritasium")
        #expect(result.videos.map(\.id) == ["v1", "v2"])
        let first = try #require(result.videos.first)
        #expect(first.title == "Quantum & you")
        #expect(first.isShort == false)
        #expect(first.summary.contains("1:59 Race"))
        #expect(first.viewCount == nil)
        #expect(first.publishedAt == ISO8601DateFormatter().date(from: "2026-11-05T10:00:00Z"))
        #expect(first.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/v1/hqdefault.jpg")
        #expect(result.videos[1].isShort)
    }

    @Test func brokenXMLThrows() {
        #expect(throws: (any Error).self) { try RSSFeed.parse(Data("<feed><entry>".utf8), channelId: "UCx") }
    }
}
