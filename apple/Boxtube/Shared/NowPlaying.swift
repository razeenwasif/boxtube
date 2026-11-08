import Foundation
import MediaPlayer
import BoxtubeCore
import BoxtubePlayer
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Publishes the current video to the lock screen / Control Center and answers its buttons.
/// The YouTube embed only gives the system a title, with no position, so Boxtube supplies the real one.
@MainActor
final class NowPlaying {
    private weak var model: AppModel?
    private var videoId: String?
    private var lastTime: Double = 0
    private var lastStamp = Date.distantPast
    private var lastPlaying = false
    private var lastRate: Double = 1
    private var artwork: MPMediaItemArtwork?

    init(model: AppModel) {
        self.model = model
        let c = MPRemoteCommandCenter.shared()
        Self.on(c.playCommand) { [weak model] in model?.player.play() }
        Self.on(c.pauseCommand) { [weak model] in model?.player.pause() }
        Self.on(c.togglePlayPauseCommand) { [weak model] in model?.player.toggle() }
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.preferredIntervals = [10]
        Self.on(c.skipForwardCommand) { [weak model] in model?.player.skip(10) }
        Self.on(c.skipBackwardCommand) { [weak model] in model?.player.skip(-10) }
        Self.on(c.nextTrackCommand) { [weak model] in model?.advanceQueue() }
        Self.onSeek(c.changePlaybackPositionCommand) { [weak model] t in model?.player.seek(to: t) }
    }

    /// Called on every player tick; only writes when something the system can't extrapolate changed.
    func update(video: Video?, state: PlayerEngine.State) {
        guard let video else {
            if videoId != nil { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; videoId = nil }
            return
        }
        let expected = lastTime + (lastPlaying ? Date.now.timeIntervalSince(lastStamp) * lastRate : 0)
        let changed = video.id != videoId || state.isPlaying != lastPlaying || state.rate != lastRate || abs(state.time - expected) > 2
        guard changed else { return }
        if video.id != videoId {
            videoId = video.id
            artwork = nil
            loadArtwork(video)
        }
        lastTime = state.time
        lastStamp = .now
        lastPlaying = state.isPlaying
        lastRate = state.rate
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.title,
            MPMediaItemPropertyArtist: video.channelTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.time,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? state.rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if state.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = state.duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = state.isPlaying ? .playing : .paused
        #endif
    }

    private func loadArtwork(_ video: Video) {
        let id = video.id
        let url = video.bestThumbnail
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url), let art = Self.artwork(data) else { return }
            guard let self, self.videoId == id else { return }
            self.artwork = art
            if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                info[MPMediaItemPropertyArtwork] = art
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }

    // MediaPlayer calls command handlers and the artwork callback on its own queue,
    // so none of these closures may be main-actor isolated.

    nonisolated private static func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor @Sendable () -> Void) {
        command.addTarget { _ in
            Task { @MainActor in action() }
            return .success
        }
    }

    nonisolated private static func onSeek(_ command: MPChangePlaybackPositionCommand, _ action: @escaping @MainActor @Sendable (Double) -> Void) {
        command.addTarget { event in
            guard let t = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor in action(t) }
            return .success
        }
    }

    nonisolated private static func artwork(_ data: Data) -> MPMediaItemArtwork? {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        #else
        guard let image = NSImage(data: data) else { return nil }
        #endif
        nonisolated(unsafe) let img = image
        return MPMediaItemArtwork(boundsSize: img.size) { _ in img }
    }
}
