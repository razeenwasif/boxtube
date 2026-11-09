import AppKit
import SwiftUI

/// Boxtube's menu bar icon and its player panel.
///
/// This replaces SwiftUI's `MenuBarExtra`, which on macOS 27 kept redrawing its icon in a loop:
/// every redraw changed the icon's appearance, which asked SwiftUI to update the icon again. That cost
/// a steady share of the main thread even with Boxtube idle. AppKit draws this icon once.
@MainActor
final class MenuBarStatusItem: NSObject, NSWindowDelegate {
    private static var shared: MenuBarStatusItem?

    /// Adds the icon once per launch.
    static func install(model: AppModel) {
        guard shared == nil else { return }
        shared = MenuBarStatusItem(model: model)
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?

    private init(model: AppModel) {
        self.model = model
        super.init()
        if let button = item.button {
            let image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Boxtube")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(toggle(_:))
        }
    }

    @objc private func toggle(_ sender: Any?) {
        if let panel, panel.isVisible { close() } else { show() }
    }

    private func close() { panel?.orderOut(nil) }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Under the icon, like a menu bar window, kept on screen.
    private func place(_ panel: NSPanel) {
        guard let button = item.button, let window = button.window, let hosting else { return }
        let size = hosting.fittingSize
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 6)
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func makePanel() -> NSPanel {
        let root = MenuBarPlayer(close: { [weak self] in self?.close() }, resized: { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            self.place(panel)
        })
        .environment(model)
        .preferredColorScheme(.dark)
        let hosting = NSHostingView(rootView: AnyView(root))
        self.hosting = hosting

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = background
        panel.delegate = self
        return panel
    }

    // Clicking anywhere else closes it, like a menu.
    func windowDidResignKey(_ notification: Notification) { close() }
}

/// A borderless panel that can still take key focus, so its buttons and resign-to-close work.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
