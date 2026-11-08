import SwiftUI
import AppKit

/// Places the window's close / minimise / zoom buttons where the Mac artboards draw them:
/// a row inside the sidebar panel, a column inside the Watch icon rail, or a row in the Music library pane.
/// `centers` are the three button centres, measured from the window's top-left corner.
struct TrafficLightPositioner: NSViewRepresentable {
    var centers: [CGPoint]

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.centers = centers
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.centers = centers
        if let window = view.window { view.position(window) }
    }

    final class TrackingView: NSView {
        var centers: [CGPoint] = []
        private var observers: [NSObjectProtocol] = []

        func position(_ window: NSWindow) {
            guard centers.count == 3,
                  let close = window.standardWindowButton(.closeButton),
                  let titlebarView = close.superview,
                  let container = titlebarView.superview else { return }
            let height = (centers.map(\.y).max() ?? 38) + 16
            container.frame = NSRect(x: 0, y: window.frame.height - height, width: window.frame.width, height: height)
            titlebarView.frame = container.bounds
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (i, type) in types.enumerated() {
                guard let button = window.standardWindowButton(type) else { continue }
                let c = centers[i]
                button.setFrameOrigin(NSPoint(x: c.x - button.frame.width / 2, y: height - c.y - button.frame.height / 2))
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                              NSWindow.didBecomeKeyNotification, NSWindow.didExitFullScreenNotification]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if let self, let w = self.window { self.position(w) } }
                })
            }
            DispatchQueue.main.async { [weak self] in if let self, let w = self.window { self.position(w) } }
        }

        override func layout() {
            super.layout()
            if let window { position(window) }
        }
    }
}
