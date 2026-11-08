import Foundation
import ActivityKit
import BoxtubeCore
import BoxtubePlayer

/// Idea 05: mirrors playback into a Live Activity (lock screen + Dynamic Island).
@MainActor
final class LiveActivityController {
    private var activity: Activity<PlaybackActivityAttributes>?
    private var lastPushed = Date.distantPast
    private var lastChapter: Int?
    private var lastPlaying: Bool?
    private weak var model: AppModel?

    func attach(to model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        model.onPlaybackChanged = { [weak self] video, state in self?.update(video: video, state: state) }
        PlaybackIntentBridge.handler = { [weak model] command in
            guard let model else { return }
            switch command {
            case .toggle: model.player.toggle()
            case .back: model.player.skip(-10)
            case .forward: model.player.skip(10)
            }
        }
        // Push immediately on play/pause and chapter changes, not only on the 5 s progress tick.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let model = self.model else { return }
                let s = model.player.state
                let chapter = model.player.video.flatMap { Chapter.current(in: $0.chapters, at: s.time)?.index }
                if s.isPlaying != self.lastPlaying || chapter != self.lastChapter {
                    self.update(video: model.player.video, state: s)
                }
            }
        }
    }

    func update(video: Video?, state: PlayerEngine.State) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let video else { end(); return }
        let chapters = video.chapters
        let current = Chapter.current(in: chapters, at: state.time)
        lastPlaying = state.isPlaying
        lastChapter = current?.index
        let content = PlaybackActivityAttributes.ContentState(
            position: state.time, duration: state.duration, isPlaying: state.isPlaying,
            chapterTitle: current?.title, chapterIndex: current?.index, chapterCount: chapters.count,
            chapterStarts: chapters.map(\.start)
        )
        if let activity, activity.attributes.videoId == video.id {
            nonisolated(unsafe) let current = activity
            Task { await current.update(ActivityContent(state: content, staleDate: .now.addingTimeInterval(120))) }
        } else {
            end()
            let attributes = PlaybackActivityAttributes(videoId: video.id, title: video.title, channel: video.channelTitle)
            activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: content, staleDate: .now.addingTimeInterval(120)))
        }
        lastPushed = .now
    }

    func end() {
        guard let activity else { return }
        nonisolated(unsafe) let ending = activity
        Task { await ending.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
