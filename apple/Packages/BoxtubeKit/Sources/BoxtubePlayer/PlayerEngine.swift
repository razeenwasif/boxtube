import SwiftUI
import WebKit
import BoxtubeCore

/// One WKWebView running the official YouTube IFrame Player, created once and moved between screens.
/// Everything time-based in the app reads `state`.
@MainActor
@Observable
public final class PlayerEngine: NSObject {
    public struct State: Equatable, Sendable {
        public var videoId: String?
        public var time: Double = 0
        public var duration: Double = 0
        public var loaded: Double = 0
        public var isPlaying = false
        public var isBuffering = false
        public var isReady = false
        public var rate: Double = 1
        public var ended = false
        public var errorCode: Int?

        public var progress: Double { duration > 0 ? min(1, time / duration) : 0 }
        public var remaining: Double { max(0, duration - time) }
    }

    public private(set) var state = State()
    public private(set) var video: Video?
    public var queue: [Video] = []

    /// Called roughly every 5 s and on pause, so the app can persist progress and update Live Activities.
    public var onProgress: ((Video, State) -> Void)?
    public var onEnded: ((Video) -> Void)?

    public let webView: WKWebView
    /// Surfaces that want the video; the most recent one shows it.
    public private(set) var hostStack: [UUID] = []
    public var owner: UUID? { hostStack.last }
    public func claim(_ id: UUID) { hostStack.removeAll { $0 == id }; hostStack.append(id) }
    public func release(_ id: UUID) { hostStack.removeAll { $0 == id } }
    private var lastProgressReport = Date.distantPast
    private let messageProxy = MessageProxy()
    /// Scripts sent before the player page has loaded wait here, so an early load isn't lost.
    private var pageLoaded = false
    private var queued: [String] = []

    /// `muted` makes a silent player for previews: it starts muted and stays muted.
    public init(muted: Bool = false) {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        #endif
        config.userContentController.add(messageProxy, name: "bt")
        webView = PlayerWebView(frame: CGRect(x: 0, y: 0, width: 16, height: 9), configuration: config)
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Boxtube draws every control itself; touches must reach its SwiftUI gestures (tap, pinch to Skim,
        // swipes in Shorts), not YouTube's own overlay inside the page.
        webView.isUserInteractionEnabled = false
        #else
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        webView.isInspectable = true
        super.init()
        self.muted = muted
        messageProxy.owner = self
        webView.navigationDelegate = messageProxy
        if let url = Bundle.module.url(forResource: "player", withExtension: "html"), var html = try? String(contentsOf: url, encoding: .utf8) {
            if muted { html = html.replacingOccurrences(of: "var startMuted = false;", with: "var startMuted = true;") }
            // A real https origin makes YouTube accept the embed (it checks the referrer).
            webView.loadHTMLString(html, baseURL: URL(string: "https://boxtube.app"))
        }
    }

    // MARK: Commands

    public func load(_ video: Video, at start: Double = 0, autoplay: Bool = true) {
        self.video = video
        state = State(videoId: video.id, duration: Double(video.durationSeconds ?? 0), isReady: state.isReady, rate: state.rate)
        state.time = start
        js("load('\(video.id)', \(Int(start)), \(autoplay))")
    }

    public func play() { js("cmd('play')"); state.isPlaying = true }
    public func pause() { js("cmd('pause')"); state.isPlaying = false; reportProgress(force: true) }
    public func toggle() { state.isPlaying ? pause() : play() }

    public func seek(to seconds: Double) {
        let clamped = max(0, state.duration > 0 ? min(seconds, state.duration - 0.5) : seconds)
        state.time = clamped
        js("cmd('seek', \(clamped))")
    }

    public func skip(_ delta: Double) { seek(to: state.time + delta) }

    public func setRate(_ rate: Double) { state.rate = rate; js("cmd('rate', \(rate))") }

    public private(set) var muted = false
    public func setMuted(_ on: Bool) { muted = on; js(on ? "cmd('mute')" : "cmd('unmute')") }
    /// For previews: whether videos loaded from now on start silent, applied to the current one too.
    public func setStartMuted(_ on: Bool) { muted = on; js("startMuted = \(on); cmd('\(on ? "mute" : "unmute")')") }

    public private(set) var captionsOn = false
    public func setCaptions(_ on: Bool) { captionsOn = on; js("cmd('cc', \(on))") }

    public func playNextInQueue() -> Bool {
        guard let next = queue.first else { return false }
        queue.removeFirst()
        load(next)
        return true
    }

    public func stop() {
        pause()
        video = nil
        state = State(isReady: state.isReady)
    }

    private func js(_ script: String) {
        guard pageLoaded else { queued.append(script); return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    fileprivate func pageDidLoad() {
        pageLoaded = true
        let scripts = queued
        queued = []
        scripts.forEach { webView.evaluateJavaScript($0, completionHandler: nil) }
    }

    // MARK: Messages from the page

    fileprivate func receive(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            state.isReady = true
        case "time":
            let t = (body["time"] as? Double) ?? state.time
            let d = (body["duration"] as? Double) ?? 0
            if abs(t - state.time) > 0.05 { state.time = t }
            if d > 0, abs(d - state.duration) > 0.5 { state.duration = d }
            state.loaded = (body["loaded"] as? Double) ?? state.loaded
            reportProgress(force: false)
        case "state":
            let code = body["state"] as? Int ?? -1
            if let d = body["duration"] as? Double, d > 0 { state.duration = d }
            state.isPlaying = code == 1
            state.isBuffering = code == 3
            state.ended = code == 0
            if code == 2 { reportProgress(force: true) }
            if code == 0, let video {
                reportProgress(force: true)
                onEnded?(video)
            }
        case "rate":
            state.rate = body["rate"] as? Double ?? state.rate
        case "error":
            state.errorCode = body["code"] as? Int
        default:
            break
        }
    }

    private func reportProgress(force: Bool) {
        guard let video, state.duration > 0 else { return }
        if force || Date.now.timeIntervalSince(lastProgressReport) > 5 {
            lastProgressReport = .now
            onProgress?(video, state)
        }
    }
}

/// The player's web view. On Mac it can refuse the mouse, so clicks and hovering reach Boxtube's own controls
/// (previews, the corner player) instead of YouTube's page.
public final class PlayerWebView: WKWebView {
    #if os(macOS)
    var passesThrough = false
    public override func hitTest(_ point: NSPoint) -> NSView? { passesThrough ? nil : super.hitTest(point) }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { passesThrough ? false : super.acceptsFirstMouse(for: event) }
    #endif
}

/// WKScriptMessageHandler retains its handler; this proxy breaks the cycle. It also hears when the page has loaded.
private final class MessageProxy: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var owner: PlayerEngine?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated { owner?.receive(body) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { owner?.pageDidLoad() }
    }
}

// MARK: - Surface

/// Shows the shared web view. Whichever surface appeared last owns it.
public struct PlayerSurface: View {
    let engine: PlayerEngine
    var interactive: Bool
    @State private var id = UUID()
    /// `interactive: false` lets clicks and hovering pass through to what's underneath (Mac previews).
    public init(engine: PlayerEngine, interactive: Bool = true) { self.engine = engine; self.interactive = interactive }
    public var body: some View {
        Host(engine: engine, isOwner: engine.owner == id, interactive: interactive)
            .background(Color.black)
            .onAppear { engine.claim(id) }
            .onDisappear { engine.release(id) }
            .accessibilityLabel("Video player")
    }
}

#if os(iOS)
private struct Host: UIViewRepresentable {
    let engine: PlayerEngine
    var isOwner: Bool
    var interactive: Bool
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        container.isUserInteractionEnabled = false
        if isOwner { attach(to: container) }
        return container
    }
    func updateUIView(_ view: UIView, context: Context) {
        if isOwner, engine.webView.superview !== view { attach(to: view) }
    }
    private func attach(to container: UIView) {
        let web = engine.webView
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
#else
private struct Host: NSViewRepresentable {
    let engine: PlayerEngine
    var isOwner: Bool
    var interactive: Bool

    /// Hands the mouse to whatever is behind it when the surface isn't interactive.
    final class Container: NSView {
        var interactive = true
        override func hitTest(_ point: NSPoint) -> NSView? { interactive ? super.hitTest(point) : nil }
    }

    func makeNSView(context: Context) -> NSView {
        let container = Container()
        container.interactive = interactive
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.masksToBounds = true
        if isOwner { attach(to: container) }
        return container
    }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? Container)?.interactive = interactive
        if isOwner, engine.webView.superview !== view { attach(to: view) }
        if isOwner { (engine.webView as? PlayerWebView)?.passesThrough = !interactive }
    }
    private func attach(to container: NSView) {
        let web = engine.webView
        (web as? PlayerWebView)?.passesThrough = !interactive
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
#endif
