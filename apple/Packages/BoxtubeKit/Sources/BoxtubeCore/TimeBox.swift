import Foundation

/// Idea 01: fill an exact amount of time from the user's own queue.
public enum TimeBoxSolver {
    public struct Pick: Hashable, Sendable, Identifiable {
        public var video: Video
        public var start: Double
        public var end: Double
        public var reason: String
        public var id: String { video.id + "-\(Int(start))" }
        public var length: Double { end - start }
    }

    public struct Box: Sendable {
        public var picks: [Pick]
        public var budget: Double
        public var total: Double { picks.reduce(0) { $0 + $1.length } }
        public var spare: Double { max(0, budget - total) }
    }

    public struct Candidate: Sendable {
        public var video: Video
        public var reason: String
        public var priority: Double
        public init(video: Video, reason: String, priority: Double) {
            self.video = video; self.reason = reason; self.priority = priority
        }
    }

    /// Bounded knapsack over whole videos plus single chapters, maximising filled time with a small
    /// bonus for higher-priority items. Durations are bucketed to 15 s so the table stays small.
    public static func build(budget: Double, from candidates: [Candidate], shuffleSeed: Int = 0) -> Box {
        let bucket = 15.0
        let cap = Int(budget / bucket)
        guard cap > 0 else { return Box(picks: [], budget: budget) }

        var items: [(pick: Pick, weight: Int, value: Double)] = []
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: shuffleSeed &+ 1))
        for (offset, c) in candidates.enumerated() {
            guard let duration = c.video.durationSeconds, duration > 0 else { continue }
            let jitter = shuffleSeed == 0 ? 0 : Double.random(in: 0...0.4, using: &rng)
            let bonus = (c.priority + jitter) * 0.08 - Double(offset) * 0.001
            let whole = Pick(video: c.video, start: 0, end: Double(duration), reason: c.reason)
            items.append((whole, Int((Double(duration) / bucket).rounded(.up)), Double(duration) / bucket + bonus * 10))
            for chapter in c.video.chapters where chapter.length >= 120 {
                let part = Pick(video: c.video, start: chapter.start, end: chapter.end,
                                reason: "\(c.video.channelTitle) · chapter \(chapter.index + 1) only")
                items.append((part, Int((chapter.length / bucket).rounded(.up)), chapter.length / bucket + bonus * 6))
            }
        }

        // dp[w] = best value, choice[w] = item indices
        var dp = Array(repeating: 0.0, count: cap + 1)
        var choice = Array(repeating: [Int](), count: cap + 1)
        for (i, item) in items.enumerated() where item.weight <= cap {
            for w in stride(from: cap, through: item.weight, by: -1) {
                let prev = choice[w - item.weight]
                // one pick per video
                if prev.contains(where: { items[$0].pick.video.id == item.pick.video.id }) { continue }
                let candidate = dp[w - item.weight] + item.value
                if candidate > dp[w] {
                    dp[w] = candidate
                    choice[w] = prev + [i]
                }
            }
        }
        let best = (0...cap).max { dp[$0] < dp[$1] } ?? 0
        let picks = choice[best].map { items[$0].pick }
        return Box(picks: picks, budget: budget)
    }
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
