import Testing
import Foundation
@testable import BoxtubeCore

@Test func isoDurations() {
    #expect(ISODuration.seconds("PT42M10S") == 2530)
    #expect(ISODuration.seconds("PT3H2M44S") == 10964)
    #expect(ISODuration.seconds("P1DT1S") == 86401)
}

@Test func chaptersFromDescription() {
    let text = """
    Intro text
    0:00 Lexing
    5:54 - Grammar
    15:11 Parsing
    (22:46) IR & passes
    """
    let chapters = ChapterParser.parse(text, duration: 2530)
    #expect(chapters.map(\.title) == ["Lexing", "Grammar", "Parsing", "IR & passes"])
    #expect(chapters.last?.end == 2530)
}

@Test func timeBoxFits() {
    func v(_ id: String, _ d: Int) -> Video { Video(id: id, channelId: "c", channelTitle: "C", title: id, publishedAt: .now, durationSeconds: d) }
    let box = TimeBoxSolver.build(budget: 25 * 60, from: [
        .init(video: v("a", 1107), reason: "", priority: 1),
        .init(video: v("b", 1623), reason: "", priority: 1),
        .init(video: v("c", 252), reason: "", priority: 1),
        .init(video: v("d", 58), reason: "", priority: 1),
    ])
    #expect(box.total <= 25 * 60)
    #expect(box.total >= 1400)
}

@Test func rssParse() throws {
    let xml = """
    <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
    <title>Kernel Panic</title><author><name>Kernel Panic</name></author>
    <entry><yt:videoId>abc123</yt:videoId><title>Hello</title><link rel="alternate" href="https://www.youtube.com/shorts/abc123"/>
    <published>2026-11-01T10:00:00+00:00</published>
    <media:group><media:description>0:00 a</media:description><media:community><media:starRating count="12"/><media:statistics views="3400"/></media:community></media:group>
    </entry></feed>
    """
    let result = try RSSFeed.parse(Data(xml.utf8), channelId: "UCx")
    #expect(result.channel.title == "Kernel Panic")
    #expect(result.videos.first?.isShort == true)
    #expect(result.videos.first?.viewCount == 3400)
}
