import Foundation

// MARK: - Chapters from description timestamps

public enum ChapterParser {
    /// YouTube rule of thumb: chapters start at 0:00 and there are at least 3 of them.
    public static func parse(_ text: String, duration: Int?) -> [Chapter] {
        var found: [(Double, String)] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let match = line.firstMatch(of: /(?:^|\s|\()((?:\d{1,2}:)?\d{1,2}:\d{2})(?:\)|\s|$|[-–—:|])/) else { continue }
            let stamp = String(match.1)
            guard let seconds = seconds(fromTimestamp: stamp) else { continue }
            var title = line.replacingOccurrences(of: stamp, with: "")
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:|()[]•·\t"))
            if title.isEmpty { title = "Chapter \(found.count + 1)" }
            found.append((seconds, title))
        }
        found.sort { $0.0 < $1.0 }
        // Drop duplicates
        var unique: [(Double, String)] = []
        for item in found where unique.last?.0 != item.0 { unique.append(item) }
        guard unique.count >= 3, unique.first?.0 == 0 else { return [] }
        let total = Double(duration ?? 0)
        return unique.enumerated().map { index, item in
            let end = index + 1 < unique.count ? unique[index + 1].0 : max(total, item.0 + 1)
            return Chapter(index: index, title: item.1, start: item.0, end: end)
        }
    }

    public static func seconds(fromTimestamp stamp: String) -> Double? {
        let parts = stamp.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return Double(parts.reduce(0) { $0 * 60 + $1 })
    }
}

// MARK: - ISO 8601 durations (PT1H2M3S)

public enum ISODuration {
    public static func seconds(_ value: String) -> Int? {
        guard value.hasPrefix("P") else { return nil }
        var total = 0
        var number = ""
        var inTime = false
        for char in value.dropFirst() {
            if char == "T" { inTime = true; continue }
            if char.isNumber { number.append(char); continue }
            let n = Int(number) ?? 0
            number = ""
            switch (char, inTime) {
            case ("D", _): total += n * 86_400
            case ("H", true): total += n * 3_600
            case ("M", true): total += n * 60
            case ("S", true): total += n
            case ("W", false): total += n * 604_800
            default: break
            }
        }
        return total
    }
}

// MARK: - Formatting

public enum Format {
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    public static func clock(_ seconds: Int?) -> String? {
        guard let seconds else { return nil }
        return clock(Double(seconds))
    }

    public static func minutes(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        if m >= 60 { return "\(m / 60) h \(m % 60) min" }
        return "\(max(1, m)) min"
    }

    public static func count(_ value: Int?) -> String? {
        guard let value else { return nil }
        switch value {
        case 1_000_000_000...: return trimmed(Double(value) / 1_000_000_000) + "B"
        case 1_000_000...: return trimmed(Double(value) / 1_000_000) + "M"
        case 1_000...: return trimmed(Double(value) / 1_000) + "K"
        default: return "\(value)"
        }
    }

    public static func views(_ value: Int?) -> String? {
        count(value).map { "\($0) views" }
    }

    private static func trimmed(_ v: Double) -> String {
        v >= 100 ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".0", with: "")
    }

    public static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return plural(Int(seconds / 60), "minute") + " ago"
        case ..<86_400: return plural(Int(seconds / 3600), "hour") + " ago"
        case ..<604_800: return plural(Int(seconds / 86_400), "day") + " ago"
        case ..<2_629_800: return plural(Int(seconds / 604_800), "week") + " ago"
        case ..<31_557_600: return plural(Int(seconds / 2_629_800), "month") + " ago"
        default: return plural(Int(seconds / 31_557_600), "year") + " ago"
        }
    }

    public static func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
}
