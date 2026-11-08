import SwiftUI
import AppKit

/// Moves the window's close/minimise/zoom buttons inside the floating sidebar panel (macOS · Home mockup):
/// 12 pt lights, 20 pt apart, centred on the panel's first row.
struct TrafficLightPositioner: NSViewRepresentable {
    var origin: CGPoint      // left edge of the first light, from the window's top-left
    var rowCenterY: CGFloat  // vertical centre of the row, from the window's top

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.apply = { window in position(window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window { position(window) }
    }

    private func position(_ window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let titlebarView = close.superview,
              let container = titlebarView.superview else { return }
        let height = rowCenterY * 2
        container.frame = NSRect(x: 0, y: window.frame.height - height, width: window.frame.width, height: height)
        titlebarView.frame = container.bounds
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (i, type) in types.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            let y = (titlebarView.bounds.height - button.frame.height) / 2
            button.setFrameOrigin(NSPoint(x: origin.x + CGFloat(i) * 20, y: y))
        }
    }

    final class TrackingView: NSView {
        var apply: ((NSWindow) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                              NSWindow.didBecomeKeyNotification, NSWindow.didExitFullScreenNotification]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    guard let window = self?.window else { return }
                    MainActor.assumeIsolated { self?.apply?(window) }
                })
            }
            DispatchQueue.main.async { [weak self] in if let w = self?.window { self?.apply?(w) } }
        }

        override func layout() {
            super.layout()
            if let window { apply?(window) }
        }
    }
}
