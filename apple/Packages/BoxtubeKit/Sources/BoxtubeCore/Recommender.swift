import Foundation
import GRDB

/// A video picked for you, with the main reason it was picked.
public struct Recommendation: Hashable, Identifiable, Sendable {
    public var video: Video
    public var score: Double
    public var reason: String
    public var id: String { video.id }
    public init(video: Video, score: Double, reason: String) { self.video = video; self.score = score; self.reason = reason }
}

/// Boxtube's own recommendations. Everything runs on the device from your library; nothing leaves it.
///
/// 1. **Profile.** Every signal (finishing, watching part, abandoning early, liking, disliking, saving,
///    adding to a playlist) adds a weight to the video's channel, its title's words and its category.
///    Weights fade with a 30-day half-life, so recent taste counts most.
/// 2. **Score.** Each candidate is scored on channel affinity, title-word match (words weighted by how
///    rare they are, so "video" counts for little and "rust" for a lot), category, freshness, how well
///    its length suits you, and whether it's doing well for its channel.
/// 3. **Mix.** A greedy pass limits videos per channel, spreads out near-identical titles, and keeps every
///    sixth slot for something you haven't been watching. A tiny per-day jitter keeps the order stable
///    within a day but different tomorrow.
public enum Recommender {
    // MARK: Input

    public struct Event: Sendable {
        public enum Kind: Sendable, CaseIterable { case finished, watched, sampled, abandoned, liked, disliked, saved, playlisted }
        public var video: Video
        public var kind: Kind
        public var at: Date
        public init(video: Video, kind: Kind, at: Date) { self.video = video; self.kind = kind; self.at = at }

        public var weight: Double {
            switch kind {
            case .finished: 1.0
            case .watched: 0.6
            case .sampled: 0.2
            case .abandoned: -0.4
            case .liked: 1.5
            case .disliked: -2.0
            case .saved: 0.5
            case .playlisted: 0.8
            }
        }
    }

    public struct Input: Sendable {
        public var candidates: [Video]
        public var events: [Event]
        public var subscribed: Set<String>
        /// Videos you've started but not finished (0.05–0.85), lightly held back: they're in Continue watching.
        public var inProgress: Set<String>
        public init(candidates: [Video], events: [Event], subscribed: Set<String>, inProgress: Set<String> = []) {
            self.candidates = candidates; self.events = events; self.subscribed = subscribed; self.inProgress = inProgress
        }
    }

    // MARK: Tuning

    static let halfLifeDays = 30.0
    static let freshnessDays = 5.0
    static let perChannelPenalty = 0.6
    static let similarityPenalty = 0.25
    static let explorationEvery = 6
    /// Every third slot goes to a channel you don't follow, when there's a good one.
    static let outsideEvery = 3

    // MARK: Profile

    struct Profile {
        var channel: [String: Double] = [:]
        var finishedByChannel: [String: Int] = [:]
        var terms: [String: Double] = [:]
        var category: [String: Double] = [:]
        var preferredDuration: Double?
    }

    static func profile(from events: [Event], tokens eventTokens: [Set<String>], idf: [String: Double], now: Date) -> Profile {
        var p = Profile()
        var durations: [(Double, Double)] = []
        for (e, toks) in zip(events, eventTokens) {
            let age = max(0, now.timeIntervalSince(e.at)) / 86_400
            let w = e.weight * pow(0.5, age / halfLifeDays)
            p.channel[e.video.channelId, default: 0] += w
            for t in toks { p.terms[t, default: 0] += w * (idf[t] ?? 1) }
            if let c = e.video.categoryId { p.category[c, default: 0] += w }
            if e.kind == .finished {
                p.finishedByChannel[e.video.channelId, default: 0] += 1
                if let d = e.video.durationSeconds, d > 0 { durations.append((Double(d), w)) }
            }
        }
        p.preferredDuration = weightedMedian(durations)
        return p
    }

    // MARK: Ranking

    struct Scored {
        var video: Video
        var tokens: Set<String>
        /// The same words as small numbers, for fast overlap checks while mixing.
        var ids: Set<Int>
        var score: Double
        var top: String
        var subscribed: Bool
        var familiar: Bool
    }

    public static func rank(_ input: Input, now: Date = .now, limit: Int = 60) -> [Recommendation] {
        guard !input.candidates.isEmpty else { return [] }
        // Titles are split into words once.
        let candidateTokens = input.candidates.map { Set(tokens($0.title)) }
        let eventTokens = input.events.map { Set(tokens($0.video.title)) }
        let idf = inverseDocumentFrequency(candidateTokens + eventTokens)
        let profile = profile(from: input.events, tokens: eventTokens, idf: idf, now: now)
        let day = Calendar(identifier: .gregorian).ordinality(of: .day, in: .era, for: now) ?? 0
        let medians = channelMedianViews(input.candidates)
        var wordIds: [String: Int] = [:]
        let candidateIds: [Set<Int>] = candidateTokens.map { toks in
            Set(toks.map { t in
                if let id = wordIds[t] { return id }
                let id = wordIds.count
                wordIds[t] = id
                return id
            })
        }

        var scored: [Scored] = zip(input.candidates, zip(candidateTokens, candidateIds)).map { v, pair in
            let (toks, ids) = pair
            let channelAffinity = profile.channel[v.channelId] ?? 0
            let subscribed = input.subscribed.contains(v.channelId)

            let channel = tanh(channelAffinity / 3)
            let topicRaw = toks.reduce(0.0) { $0 + (profile.terms[$1] ?? 0) * (idf[$1] ?? 1) } / sqrt(Double(max(1, toks.count)))
            let topic = tanh(topicRaw / 4)
            let category = v.categoryId.map { tanh((profile.category[$0] ?? 0) / 6) } ?? 0
            let ageDays = max(0, now.timeIntervalSince(v.publishedAt)) / 86_400
            let fresh = exp(-ageDays / freshnessDays)
            var lengthFit = 0.0
            if let pref = profile.preferredDuration, let d = v.durationSeconds, d > 0 {
                let x = log(Double(d) / pref)
                lengthFit = exp(-(x * x) / (2 * 0.9 * 0.9)) - 0.5
            }
            var momentum = 0.0
            if let views = v.viewCount, views > 0, let median = medians[v.channelId], median > 0 {
                momentum = tanh(log(Double(views) / median))
            }

            var score = 1.4 * channel + 1.0 * topic + 0.35 * category + 0.9 * fresh + 0.3 * lengthFit + 0.3 * momentum
            if subscribed { score += 0.3 } else if channelAffinity <= 0 { score -= 0.25 }
            if input.inProgress.contains(v.id) { score -= 0.2 }
            score += jitter(v.id, day: day)

            // The reason is the strongest personal signal that's meaningful; freshness only when there's none.
            let top = channel >= 0.45 ? "channel" : topic >= 0.3 ? "topic" : momentum >= 0.5 ? "momentum" : "fresh"
            return Scored(video: v, tokens: toks, ids: ids, score: score, top: top, subscribed: subscribed, familiar: subscribed || channelAffinity > 0.5)
        }
        // Only the strongest candidates (and the strongest unfamiliar ones, for exploring) can reach the top
        // `limit` once mixed, so the mix works on those.
        scored.sort { $0.score > $1.score }
        var pool = Array(scored.prefix(limit * 4))
        pool += scored.dropFirst(limit * 4).filter { !$0.familiar }.prefix(limit)

        // Greedy mix: penalise channels already shown and titles too close to the last few picks.
        var picked: [Recommendation] = []
        var pickedIds: [Set<Int>] = []
        var perChannel: [String: Int] = [:]
        let positive = zip(input.events, eventTokens).filter { $0.0.weight > 0 }
        while picked.count < limit, !pool.isEmpty {
            let exploring = (picked.count + 1) % explorationEvery == 0
            let recent = pickedIds.suffix(8)
            // Each round scores the pool once.
            let adjusted: [Double] = pool.map { s in
                let repeats = Double(perChannel[s.video.channelId] ?? 0)
                let similar = recent.map { jaccard($0, s.ids) }.max() ?? 0
                // Grows faster than linearly: a second video from a channel is fine, a fourth rarely is.
                return s.score - perChannelPenalty * pow(repeats, 1.5) - similarityPenalty * similar
            }
            var index: Int?
            if !exploring, (picked.count + 1) % outsideEvery == 0 {
                index = pool.indices.filter { !pool[$0].subscribed }.max { adjusted[$0] < adjusted[$1] }
            }
            if exploring {
                // Something you haven't been watching: an unfamiliar channel, best match first.
                index = pool.indices.filter { !pool[$0].familiar && perChannel[pool[$0].video.channelId] == nil }
                    .max { adjusted[$0] < adjusted[$1] }
            }
            if index == nil { index = pool.indices.max { adjusted[$0] < adjusted[$1] } }
            guard let i = index else { break }
            let score = adjusted[i]
            let s = pool.remove(at: i)
            let why = exploring && !s.familiar
                ? "Something new from \(s.video.channelTitle)"
                : reason(for: s, profile: profile, positive: positive, idf: idf)
            picked.append(Recommendation(video: s.video, score: score, reason: why))
            pickedIds.append(s.ids)
            perChannel[s.video.channelId, default: 0] += 1
        }
        return picked
    }

    // MARK: Interests

    /// What you're into, for finding videos beyond your subscriptions: your most distinctive title words,
    /// each paired with the word it most often appears with ("rust ownership", not "rust"), and your
    /// favourite categories.
    public static func interests(_ input: Input, now: Date = .now, count: Int = 3) -> (queries: [String], categories: [String]) {
        let eventTokens = input.events.map { Set(tokens($0.video.title)) }
        let idf = inverseDocumentFrequency(input.candidates.map { Set(tokens($0.title)) } + eventTokens)
        let profile = profile(from: input.events, tokens: eventTokens, idf: idf, now: now)
        // Channel names say who, not what: leave them out.
        let names = Set(input.events.flatMap { tokens($0.video.channelTitle) })
        let top = profile.terms.filter { $0.value > 0 && !names.contains($0.key) }
            .sorted { $0.value > $1.value }.prefix(count).map(\.key)
        let positive = zip(input.events, eventTokens).filter { $0.0.weight > 0 }.map(\.1)
        let queries = top.map { term -> String in
            var together: [String: Int] = [:]
            for toks in positive where toks.contains(term) {
                for t in toks where t != term && !names.contains(t) { together[t, default: 0] += 1 }
            }
            guard let partner = together.filter({ $0.value >= 2 }).max(by: { $0.value < $1.value })?.key else { return term }
            return "\(term) \(partner)"
        }
        let categories = profile.category.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(count).map(\.key)
        return (queries, categories)
    }

    // MARK: Reasons

    /// Worked out only for the videos that are picked.
    static func reason(for s: Scored, profile: Profile, positive: [(Event, Set<String>)], idf: [String: Double]) -> String {
        let v = s.video
        switch s.top {
        case "channel" where (profile.finishedByChannel[v.channelId] ?? 0) >= 2:
            return "You often finish \(v.channelTitle)'s videos"
        case "channel":
            return "You've been watching \(v.channelTitle)"
        case "topic":
            // The liked or watched video that shares the most distinctive words with this one.
            var best: (Event, Double)?
            for (e, toks) in positive where e.video.id != v.id {
                let overlap = toks.intersection(s.tokens).reduce(0.0) { $0 + (idf[$1] ?? 1) }
                if overlap > (best?.1 ?? 0) { best = (e, overlap) }
            }
            if let (e, _) = best {
                let title = shortened(e.video.title)
                return e.kind == .liked ? "Because you liked “\(title)”" : "Because you watched “\(title)”"
            }
            return s.subscribed ? "New from \(v.channelTitle)" : "Something new from \(v.channelTitle)"
        case "momentum":
            return "Doing well for \(v.channelTitle)"
        default:
            return s.subscribed ? "New from \(v.channelTitle)" : "Something new from \(v.channelTitle)"
        }
    }

    static func shortened(_ title: String, max: Int = 38) -> String {
        title.count <= max ? title : String(title.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: Text

    static let stopwords: Set<String> = [
        "the", "and", "for", "with", "you", "your", "this", "that", "how", "what", "why", "from", "are", "was", "were",
        "all", "our", "its", "can", "not", "but", "out", "get", "has", "his", "her", "they", "them", "will", "just",
        "into", "more", "most", "than", "then", "when", "who", "about", "after", "over", "video", "videos", "official",
        "episode", "part", "full", "new", "now", "here", "there", "have", "one", "two", "my", "me", "is", "it", "in",
        "on", "of", "to", "a", "an", "i", "we", "be", "do", "so", "if", "at", "by", "or", "as", "no", "vs", "ft", "feat",
        "ever", "every", "first", "best", "make", "made", "way", "day", "time", "really", "very", "much", "some", "any",
    ]

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { $0.count >= 3 && !stopwords.contains($0) && !$0.allSatisfy(\.isNumber) }
    }

    static func inverseDocumentFrequency(_ docs: [Set<String>]) -> [String: Double] {
        var df: [String: Int] = [:]
        for d in docs { for t in d { df[t, default: 0] += 1 } }
        let n = Double(docs.count)
        return df.mapValues { log((n + 1) / (Double($0) + 1)) + 1 }
    }

    static func jaccard<T>(_ a: Set<T>, _ b: Set<T>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    // MARK: Numbers

    static func weightedMedian(_ values: [(Double, Double)]) -> Double? {
        let positive = values.filter { $0.1 > 0 }.sorted { $0.0 < $1.0 }
        let total = positive.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var running = 0.0
        for (v, w) in positive {
            running += w
            if running >= total / 2 { return v }
        }
        return positive.last?.0
    }

    static func channelMedianViews(_ videos: [Video]) -> [String: Double] {
        Dictionary(grouping: videos.compactMap { v in v.viewCount.map { (v.channelId, Double($0)) } }, by: \.0)
            .compactMapValues { pairs in
                guard pairs.count >= 3 else { return nil }
                let sorted = pairs.map(\.1).sorted()
                return sorted[sorted.count / 2]
            }
    }

    /// ±0.04, stable for a video within a day.
    static func jitter(_ id: String, day: Int) -> Double {
        var h: UInt64 = 1469598103934665603
        for b in "\(id)#\(day)".utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return (Double(h % 10_000) / 10_000 - 0.5) * 0.08
    }
}

// MARK: - Reading the library

extension Q {
    /// Everything the recommender needs, in one read.
    public static func recommendationInput(_ db: Database, now: Date = .now, includeUnfollowed: Bool = true) throws -> Recommender.Input {
        let hiddenVideos = Set(try String.fetchAll(db, sql: "SELECT id FROM hiddenVideo"))
        let hiddenChannels = Set(try String.fetchAll(db, sql: "SELECT id FROM hiddenChannel"))
        let subscribed = Set(try String.fetchAll(db, sql: "SELECT id FROM channel WHERE isSubscribed = 1"))
        let music = Set(try String.fetchAll(db, sql: "SELECT id FROM channel WHERE isMusic = 1"))
        let disliked = try Row.fetchAll(db, sql: "SELECT videoId, dislikedAt FROM disliked")
        let dislikedIds = Set(disliked.map { $0["videoId"] as String })
        let history = try HistoryEntry.fetchAll(db)
        let finished = Set(history.filter { $0.progress >= 0.85 }.map(\.videoId))
        let inProgress = Set(history.filter { $0.progress >= 0.05 && $0.progress < 0.85 }.map(\.videoId))

        // Candidates: the last 45 days from channels you follow (and, if allowed, channels you watch but
        // don't follow), plus cached topic lists. Never Shorts, music, finished, disliked or hidden.
        let since = now.addingTimeInterval(-45 * 86_400)
        var candidates = try Video.fetchAll(db, sql: """
            SELECT video.* FROM video LEFT JOIN channel ON channel.id = video.channelId
            WHERE video.isShort = 0 AND video.isLive = 0
              AND video.id NOT IN (SELECT videoId FROM movie)
              AND ((video.publishedAt > ? AND (channel.isSubscribed = 1 OR ?))
                   OR video.id IN (SELECT videoId FROM listCache WHERE key LIKE 'topic:%' OR (? AND key LIKE 'rec:%')))
            ORDER BY video.publishedAt DESC LIMIT 900
            """, arguments: [since, includeUnfollowed, includeUnfollowed])
        candidates.removeAll {
            hiddenVideos.contains($0.id) || hiddenChannels.contains($0.channelId) || music.contains($0.channelId)
                || finished.contains($0.id) || dislikedIds.contains($0.id) || $0.isMusic
        }

        // Signals.
        var events: [Recommender.Event] = []
        let ids = Set(history.map(\.videoId))
            .union(try String.fetchAll(db, sql: "SELECT videoId FROM liked"))
            .union(dislikedIds)
            .union(try String.fetchAll(db, sql: "SELECT videoId FROM watchLater"))
            .union(try String.fetchAll(db, sql: "SELECT videoId FROM playlistItem ORDER BY addedAt DESC LIMIT 400"))
        let videos = Dictionary(uniqueKeysWithValues: try Video.fetchAll(db, keys: Array(ids)).map { ($0.id, $0) })
        for h in history {
            guard let v = videos[h.videoId] else { continue }
            let p = h.progress
            let kind: Recommender.Event.Kind? =
                p >= 0.85 ? .finished : p >= 0.4 ? .watched : p >= 0.15 ? .sampled
                : (now.timeIntervalSince(h.lastWatchedAt) > 3600 ? .abandoned : nil)
            if let kind { events.append(.init(video: v, kind: kind, at: h.lastWatchedAt)) }
        }
        for like in try LikedVideo.fetchAll(db) { if let v = videos[like.videoId] { events.append(.init(video: v, kind: .liked, at: like.likedAt)) } }
        for row in disliked { if let v = videos[row["videoId"]] { events.append(.init(video: v, kind: .disliked, at: row["dislikedAt"])) } }
        for later in try WatchLaterEntry.fetchAll(db) { if let v = videos[later.videoId] { events.append(.init(video: v, kind: .saved, at: later.savedAt)) } }
        for item in try PlaylistItem.order(Column("addedAt").desc).limit(400).fetchAll(db) {
            if let v = videos[item.videoId] { events.append(.init(video: v, kind: .playlisted, at: item.addedAt)) }
        }
        // Hidden channels are out of the picture entirely.
        events.removeAll { hiddenChannels.contains($0.video.channelId) }

        return .init(candidates: candidates, events: events, subscribed: subscribed, inProgress: inProgress)
    }

    public static func recommendations(_ db: Database, now: Date = .now, includeUnfollowed: Bool = true, limit: Int = 60) throws -> [Recommendation] {
        Recommender.rank(try recommendationInput(db, now: now, includeUnfollowed: includeUnfollowed), now: now, limit: limit)
    }

    /// Channels you don't follow but keep watching, liking or saving: their free feeds widen Home.
    public static func discoveryChannels(_ db: Database, limit: Int = 12, olderThan: Date) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT v.channelId FROM (
                SELECT videoId, 1.0 AS w FROM history
                UNION ALL SELECT videoId, 1.5 FROM liked
                UNION ALL SELECT videoId, 0.5 FROM watchLater
                UNION ALL SELECT videoId, 0.8 FROM playlistItem
            ) s
            JOIN video v ON v.id = s.videoId
            LEFT JOIN channel c ON c.id = v.channelId
            WHERE COALESCE(c.isSubscribed, 0) = 0 AND COALESCE(c.isMusic, 0) = 0
              AND v.channelId NOT IN (SELECT id FROM hiddenChannel)
              AND (c.lastFetchedAt IS NULL OR c.lastFetchedAt < ?)
            GROUP BY v.channelId
            HAVING SUM(s.w) >= 1.5
            ORDER BY SUM(s.w) DESC
            LIMIT ?
            """, arguments: [olderThan, limit])
    }
}
