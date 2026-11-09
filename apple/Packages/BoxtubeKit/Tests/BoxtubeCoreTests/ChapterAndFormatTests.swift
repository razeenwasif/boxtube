import Testing
import Foundation
@testable import BoxtubeCore

@Suite("Chapters")
struct ChapterTests {
    @Test func needsThreeChaptersStartingAtZero() {
        #expect(ChapterParser.parse("0:00 Intro\n2:00 Middle", duration: 600).isEmpty, "two timestamps aren't chapters")
        #expect(ChapterParser.parse("0:30 A\n2:00 B\n4:00 C", duration: 600).isEmpty, "chapters must start at 0:00")
        #expect(ChapterParser.parse("No timestamps here", duration: 600).isEmpty)
    }

    @Test func hourTimestampsSortedAndDeduplicated() {
        let text = """
        1:02:03 Outro
        0:00 Start
        30:00 Half way
        0:00 Start again
        """
        let chapters = ChapterParser.parse(text, duration: 4000)
        #expect(chapters.map(\.start) == [0, 1800, 3723])
        #expect(chapters.map(\.index) == [0, 1, 2])
        #expect(chapters[0].end == 1800)
        #expect(chapters[2].end == 4000)
    }

    @Test func untitledChaptersGetNumbers() {
        let chapters = ChapterParser.parse("0:00\n1:00 Named\n2:00 -", duration: 300)
        #expect(chapters.map(\.title) == ["Chapter 1", "Named", "Chapter 3"])
    }

    @Test func unknownDurationEndsLastChapterAfterItsStart() {
        let chapters = ChapterParser.parse("0:00 A\n1:00 B\n2:00 C", duration: nil)
        #expect(chapters.last?.end == 121)
    }

    @Test func timestampInTheMiddleOfALine() {
        let chapters = ChapterParser.parse("Intro (0:00)\nThe Race to Absolute Zero (1:59)\nWhy helium (6:33)", duration: 900)
        #expect(chapters.map(\.title) == ["Intro", "The Race to Absolute Zero", "Why helium"])
        #expect(chapters.map(\.start) == [0, 119, 393])
    }
}

@Suite("Durations")
struct DurationTests {
    @Test(arguments: [
        ("PT0S", 0), ("PT59S", 59), ("PT1M", 60), ("PT1H", 3600), ("P1W", 604_800), ("PT10H0M1S", 36001),
    ])
    func iso(_ text: String, _ seconds: Int) {
        #expect(ISODuration.seconds(text) == seconds)
    }

    @Test func notAnISODuration() {
        #expect(ISODuration.seconds("42:10") == nil)
        #expect(ISODuration.seconds("") == nil)
    }
}

@Suite("Formatting")
struct FormatTests {
    @Test func clock() {
        #expect(Format.clock(0) == "0:00")
        #expect(Format.clock(59.9) == "0:59")
        #expect(Format.clock(754) == "12:34")
        #expect(Format.clock(3725) == "1:02:05")
        #expect(Format.clock(-5) == "0:00")
        #expect(Format.clock(.nan) == "0:00")
        #expect(Format.clock(nil as Int?) == nil)
    }

    @Test(arguments: [
        (999, "999"), (1_000, "1K"), (1_500, "1.5K"), (12_400, "12.4K"), (150_000, "150K"),
        (2_000_000, "2M"), (21_400_000, "21.4M"), (3_400_000_000, "3.4B"),
    ])
    func counts(_ value: Int, _ text: String) {
        #expect(Format.count(value) == text)
    }

    @Test func views() {
        #expect(Format.views(1_200_000) == "1.2M views")
        #expect(Format.views(nil) == nil)
    }

    @Test func minutes() {
        #expect(Format.minutes(10) == "1 min")
        #expect(Format.minutes(25 * 60) == "25 min")
        #expect(Format.minutes(65 * 60) == "1 h 5 min")
    }

    @Test func ago() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Format.ago(now.addingTimeInterval(-30), now: now) == "just now")
        #expect(Format.ago(now.addingTimeInterval(-90), now: now) == "1 minute ago")
        #expect(Format.ago(now.addingTimeInterval(-2 * 3600), now: now) == "2 hours ago")
        #expect(Format.ago(now.addingTimeInterval(-86_400), now: now) == "1 day ago")
        #expect(Format.ago(now.addingTimeInterval(-14 * 86_400), now: now) == "2 weeks ago")
        #expect(Format.ago(now.addingTimeInterval(-400 * 86_400), now: now) == "1 year ago")
    }
}
