import SwiftUI
import Network
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

/// When thumbnails play by themselves.
enum PreviewMode: String, CaseIterable, Identifiable {
    case on, wifiOnly, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .on: "On"
        case .wifiOnly: "On Wi-Fi only"
        case .off: "Off"
        }
    }
}

/// Plays a silent preview of the video you hover (Mac) or settle on (iPhone), like YouTube's Home.
/// It has its own player, so it never touches what you're watching, and it records no history.
@MainActor
@Observable
final class PreviewController {
    private(set) var engine: PlayerEngine?
    /// The video being previewed, if any.
    private(set) var videoId: String?
    /// Turned on from a preview's sound button; later previews keep it until Boxtube restarts.
    private(set) var soundOn = false
    private var startedAt: Double = 0

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var expensiveNetwork = false
    @ObservationIgnored private let monitor = NWPathMonitor()
    // iPhone: which cards are on screen, and where.
    @ObservationIgnored private var visible: [String: Video] = [:]
    @ObservationIgnored private var midY: [String: CGFloat] = [:]
    @ObservationIgnored private var scrolling = false

    static let maxSeconds: Double = 45

    func attach(_ model: AppModel) {
        self.model = model
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive || path.isConstrained
            Task { @MainActor in self?.expensiveNetwork = expensive }
        }
        monitor.start(queue: DispatchQueue(label: "boxtube.preview.network"))
    }

    /// Whether previews may play right now.
    var allowed: Bool {
        guard let model, !model.calmMode else { return false }
        switch model.previewMode {
        case .off: return false
        case .wifiOnly: if expensiveNetwork { return false }
        case .on: break
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return false }
        #if os(iOS)
        if !UIAccessibility.isVideoAutoplayEnabled { return false }
        if model.watching != nil || model.showMusicPlayer { return false }
        #else
        if model.watching != nil { return false }
        #endif
        return true
    }

    /// True once the preview for `id` is actually moving, so the thumbnail can fade into it.
    func isShowing(_ id: String) -> Bool {
        guard videoId == id, let s = engine?.state, s.videoId == id else { return false }
        return s.isPlaying && s.time > startedAt + 0.2
    }

    var remaining: Double? {
        guard let s = engine?.state, s.duration > 0 else { return nil }
        return s.remaining
    }

    var progress: Double { engine?.state.progress ?? 0 }

    // MARK: Mac: hover

    func hover(_ video: Video, delay: Double = 0.55) {
        guard allowed, videoId != video.id else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.start(video)
        }
    }

    func leave(_ id: String) {
        if videoId == id { stop() } else { pending?.cancel() }
    }

    // MARK: iPhone: settle on a card

    func visibility(_ video: Video, _ isVisible: Bool) {
        if isVisible { visible[video.id] = video } else {
            visible[video.id] = nil
            midY[video.id] = nil
            if videoId == video.id { stop() }
        }
        if !scrolling { scheduleSettle(after: 0.9) }
    }

    func position(_ id: String, _ y: CGFloat) { midY[id] = y }

    func scrollPhase(isScrolling: Bool) {
        scrolling = isScrolling
        if isScrolling { pending?.cancel() } else { scheduleSettle(after: 0.6) }
    }

    /// Plays the fully visible card nearest the upper middle of the screen.
    private func scheduleSettle(after delay: Double) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.allowed, !self.scrolling else { return }
            let target: CGFloat = 330
            let best = self.visible.values.min { abs((self.midY[$0.id] ?? .infinity) - target) < abs((self.midY[$1.id] ?? .infinity) - target) }
            guard let best, best.id != self.videoId else { return }
            await self.start(best)
        }
    }

    // MARK: Playing

    private func start(_ video: Video) async {
        guard allowed, let model else { return }
        var at = 0.0
        if let h = try? await model.store.read({ db in try HistoryEntry.fetchOne(db, key: video.id) }), h.progress < 0.95 {
            at = h.positionSeconds
        }
        guard allowed else { return }
        let engine = self.engine ?? PlayerEngine(muted: !soundOn)
        self.engine = engine
        if soundOn, model.player.isPlaying { model.player.pause() }
        startedAt = at
        withAnimation(.easeOut(duration: 0.2)) { videoId = video.id }
        engine.load(video, at: at)
        // Stop after a while, so a forgotten hover doesn't play a whole video.
        let id = video.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxSeconds))
            if self?.videoId == id { self?.stop() }
        }
    }

    func toggleSound() {
        soundOn.toggle()
        engine?.setStartMuted(!soundOn)
        // Two soundtracks at once would be noise: pause the main video while a preview is heard.
        if soundOn, let model, model.player.isPlaying { model.player.pause() }
    }

    func stop() {
        pending?.cancel()
        guard videoId != nil else { return }
        engine?.pause()
        withAnimation(.easeOut(duration: 0.25)) { videoId = nil }
    }

    /// Where the full video should start when you open the card being previewed.
    func handoffTime(for id: String) -> Double? {
        guard videoId == id, let s = engine?.state, s.videoId == id, s.time > startedAt + 2 else { return nil }
        return s.time
    }
}

/// The preview's picture, laid over a thumbnail. Invisible until the video is actually moving.
struct PreviewLayer: View {
    @Environment(AppModel.self) private var model
    var video: Video
    var showBadge = true

    var body: some View {
        let preview = model.preview
        if preview.videoId == video.id, let engine = preview.engine {
            let showing = preview.isShowing(video.id)
            ZStack {
                PlayerSurface(engine: engine, interactive: false)
                    .overlay(alignment: .bottom) {
                        if showing { ProgressLine(value: preview.progress, height: 3).transition(.opacity) }
                    }
                    .allowsHitTesting(false)
                    // Not fully transparent: a hidden web view may stop playing.
                    .opacity(showing ? 1 : 0.01)
                if showing && showBadge {
                    SoundBadge(soundOn: preview.soundOn, remaining: preview.remaining) { preview.toggleSound() }
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: showing)
        }
    }
}

/// The preview's sound button, with the time left. It takes its own clicks, so the card doesn't open.
private struct SoundBadge: View {
    var soundOn: Bool
    var remaining: Double?
    var toggle: () -> Void
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill").font(.system(size: 10, weight: .bold))
            if let remaining { Text(Format.clock(remaining)).monospacedDigit() }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8).frame(height: 24)
        .background(.black.opacity(0.72), in: .rect(cornerRadius: 7))
        .contentShape(.rect(cornerRadius: 7))
        .highPriorityGesture(TapGesture().onEnded { toggle() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(soundOn ? "Turn preview sound off" : "Turn preview sound on")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle() }
        #if os(macOS)
        .help(soundOn ? "Mute previews" : "Play previews with sound")
        #endif
    }
}

extension View {
    /// Plays a silent preview of `video` over this thumbnail: on hover (Mac) or when it settles on screen (iPhone).
    func videoPreview(_ video: Video, cornerRadius: CGFloat) -> some View {
        overlay { PreviewLayer(video: video).clipShape(.rect(cornerRadius: cornerRadius, style: .continuous)) }
            .previewTrigger(video)
    }

    /// Hover previews on Mac grids; nothing on iPhone, where only Home's big cards preview.
    @ViewBuilder
    func macPreview(_ video: Video, cornerRadius: CGFloat, enabled: Bool = true) -> some View {
        #if os(macOS)
        if enabled { videoPreview(video, cornerRadius: cornerRadius) } else { self }
        #else
        self
        #endif
    }

    /// Starts and stops the preview for `video` without drawing it (for custom layouts like the Mac hero).
    func previewTrigger(_ video: Video) -> some View { modifier(PreviewTrigger(video: video)) }
}

private struct PreviewTrigger: ViewModifier {
    @Environment(AppModel.self) private var model
    var video: Video

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onHover { inside in
            if inside { model.preview.hover(video) } else { model.preview.leave(video.id) }
        }
        #else
        content
            .onScrollVisibilityChange(threshold: 0.9) { visible in model.preview.visibility(video, visible) }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midY } action: { y in model.preview.position(video.id, y) }
            .onDisappear { model.preview.visibility(video, false) }
        #endif
    }
}
