import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// Idea 05: shared between the app (starts/updates) and the widget extension (draws).
public struct PlaybackActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var position: Double
        public var duration: Double
        public var isPlaying: Bool
        public var chapterTitle: String?
        public var chapterIndex: Int?
        public var chapterCount: Int
        public var chapterStarts: [Double]
        public var updatedAt: Date

        public init(position: Double, duration: Double, isPlaying: Bool, chapterTitle: String?, chapterIndex: Int?,
                    chapterCount: Int, chapterStarts: [Double], updatedAt: Date = .now) {
            self.position = position; self.duration = duration; self.isPlaying = isPlaying
            self.chapterTitle = chapterTitle; self.chapterIndex = chapterIndex; self.chapterCount = chapterCount
            self.chapterStarts = chapterStarts; self.updatedAt = updatedAt
        }

        public var progress: Double { duration > 0 ? min(1, position / duration) : 0 }
        public var remaining: Double { max(0, duration - position) }
    }

    public var videoId: String
    public var title: String
    public var channel: String

    public init(videoId: String, title: String, channel: String) {
        self.videoId = videoId; self.title = title; self.channel = channel
    }
}
#endif
