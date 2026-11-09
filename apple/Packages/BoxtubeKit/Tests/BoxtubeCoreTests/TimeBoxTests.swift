import Testing
import Foundation
@testable import BoxtubeCore

@Suite("Time box")
struct TimeBoxTests {
    func video(_ id: String, _ seconds: Int?, chapters: String = "") -> Video {
        Video(id: id, channelId: "c", channelTitle: "Channel", title: id, summary: chapters, publishedAt: .now, durationSeconds: seconds)
    }
    func candidates(_ videos: [Video]) -> [TimeBoxSolver.Candidate] {
        videos.map { .init(video: $0, reason: "", priority: 1) }
    }

    @Test(arguments: [0, 1, 7, 42])
    func neverOverTheBudgetAndOneSlotPerVideo(seed: Int) {
        let videos = (0..<12).map { video("v\($0)", 120 + $0 * 173) }
        let box = TimeBoxSolver.build(budget: 25 * 60, from: candidates(videos), shuffleSeed: seed)
        #expect(box.total <= 25 * 60)
        #expect(box.total > 20 * 60, "a 25 minute box from 12 videos should be nearly full")
        let ids = box.picks.map(\.video.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func usesASingleChapterWhenTheVideoIsTooLong() {
        let long = video("long", 3600, chapters: "0:00 One\n8:00 Two\n20:00 Three\n40:00 Four")
        let box = TimeBoxSolver.build(budget: 10 * 60, from: candidates([long]))
        #expect(box.picks.count == 1)
        let pick = try? #require(box.picks.first)
        #expect(pick?.start == 0)
        #expect(pick?.end == 480)
        #expect(pick?.reason.contains("chapter 1 only") == true)
    }

    @Test func skipsVideosWithoutALength() {
        let box = TimeBoxSolver.build(budget: 600, from: candidates([video("unknown", nil), video("zero", 0)]))
        #expect(box.picks.isEmpty)
        #expect(box.spare == 600)
    }

    @Test func tinyBudgetIsEmpty() {
        let box = TimeBoxSolver.build(budget: 10, from: candidates([video("a", 5)]))
        #expect(box.picks.isEmpty)
    }
}
