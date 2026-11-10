import SwiftUI
import BoxtubeCore
import BoxtubeUI
#if os(macOS)
import AppKit
typealias PlatformView = NSView
#else
import UIKit
typealias PlatformView = UIView
#endif

// Boxtube's own menus, in place of the system's: the same dark glass panel, section labels, tinted icon
// tiles and highlighted row as the command palette (Mac) and command panel (iPhone) artboards.
//
//   BXMenuButton { BXMenuSection { BXMenuItem("Play next", icon: "…") { … } } } label: { … }
//   someView.bxContextMenu { … }        // right-click on Mac, long press on iPhone
//
// Menus draw in a `BXMenuHost` overlay at the root of each window or full-screen cover (`.bxMenuHost()`).

// MARK: - Model

struct BXMenuItem: Identifiable {
    enum Kind {
        case action(@MainActor () -> Void)
        case submenu([BXMenuSection])
        case share(URL)
        /// A line of information, not an action (e.g. why Home picked a video).
        case note
    }

    let id = UUID()
    var title: String
    var icon: String?
    var tint: Color?
    var detail: String?
    var checked = false
    var destructive = false
    var disabled = false
    var kind: Kind

    init(_ title: String, icon: String? = nil, tint: Color? = nil, detail: String? = nil, checked: Bool = false,
         destructive: Bool = false, disabled: Bool = false, action: @escaping @MainActor () -> Void) {
        self.title = title; self.icon = icon; self.tint = tint; self.detail = detail; self.checked = checked
        self.destructive = destructive; self.disabled = disabled; self.kind = .action(action)
    }

    private init(title: String, icon: String?, tint: Color?, detail: String? = nil, disabled: Bool = false, kind: Kind) {
        self.title = title; self.icon = icon; self.tint = tint; self.detail = detail; self.disabled = disabled; self.kind = kind
    }

    static func submenu(_ title: String, icon: String? = nil, tint: Color? = nil, detail: String? = nil,
                        @BXMenuBuilder _ sections: () -> [BXMenuSection]) -> BXMenuItem {
        BXMenuItem(title: title, icon: icon, tint: tint, detail: detail, kind: .submenu(sections()))
    }

    static func share(_ url: URL, title: String = "Share") -> BXMenuItem {
        BXMenuItem(title: title, icon: "square.and.arrow.up", tint: nil, kind: .share(url))
    }

    static func note(_ text: String, icon: String = "sparkles", tint: Color = BX.coralText) -> BXMenuItem {
        BXMenuItem(title: text, icon: icon, tint: tint, kind: .note)
    }

    var isActionable: Bool {
        if disabled { return false }
        if case .note = kind { return false }
        return true
    }
}

struct BXMenuSection: Identifiable {
    let id = UUID()
    var title: String?
    var items: [BXMenuItem]

    init(_ title: String? = nil, @BXMenuItemsBuilder _ items: () -> [BXMenuItem]) {
        self.title = title
        self.items = items()
    }
}

@resultBuilder
enum BXMenuItemsBuilder {
    static func buildBlock(_ parts: [BXMenuItem]...) -> [BXMenuItem] { parts.flatMap { $0 } }
    static func buildExpression(_ item: BXMenuItem) -> [BXMenuItem] { [item] }
    static func buildExpression(_ items: [BXMenuItem]) -> [BXMenuItem] { items }
    static func buildOptional(_ items: [BXMenuItem]?) -> [BXMenuItem] { items ?? [] }
    static func buildEither(first items: [BXMenuItem]) -> [BXMenuItem] { items }
    static func buildEither(second items: [BXMenuItem]) -> [BXMenuItem] { items }
    static func buildArray(_ items: [[BXMenuItem]]) -> [BXMenuItem] { items.flatMap { $0 } }
}

@resultBuilder
enum BXMenuBuilder {
    static func buildBlock(_ parts: [BXMenuSection]...) -> [BXMenuSection] { parts.flatMap { $0 } }
    static func buildExpression(_ section: BXMenuSection) -> [BXMenuSection] { [section] }
    static func buildExpression(_ sections: [BXMenuSection]) -> [BXMenuSection] { sections }
    /// A bare item becomes its own untitled section.
    static func buildExpression(_ item: BXMenuItem) -> [BXMenuSection] { [BXMenuSection { item }] }
    static func buildOptional(_ sections: [BXMenuSection]?) -> [BXMenuSection] { sections ?? [] }
    static func buildEither(first sections: [BXMenuSection]) -> [BXMenuSection] { sections }
    static func buildEither(second sections: [BXMenuSection]) -> [BXMenuSection] { sections }
    static func buildArray(_ sections: [[BXMenuSection]]) -> [BXMenuSection] { sections.flatMap { $0 } }
}

/// A choice menu (in place of `Picker`): one checked item per option.
@MainActor
func bxChoices<T: Hashable & Sendable>(_ options: [T], selected: T, title: (T) -> String, choose: @escaping @MainActor (T) -> Void) -> [BXMenuSection] {
    [BXMenuSection { options.map { o in BXMenuItem(title(o), checked: o == selected) { choose(o) } } }]
}

// MARK: - Host

/// Where menus and dialogs draw, one per window or full-screen cover.
@MainActor
@Observable
final class BXMenuHost {
    struct Shown: Identifiable {
        let id = UUID()
        var sections: [BXMenuSection]
        /// The trigger's frame in the host's coordinates (top-left origin).
        var anchor: CGRect
        /// Lines the menu up with the trigger's trailing edge instead of its leading edge.
        var trailing: Bool
        /// A context menu opens at the pointer rather than below its view.
        var atPoint: Bool
    }

    var shown: Shown?
    var dialog: BXDialog?
    @ObservationIgnored let hostRef = ViewRef()
    @ObservationIgnored private var shareRect: CGRect = .zero

    /// Opens a menu for a trigger view (below it, or above when there's no room).
    func present(_ sections: [BXMenuSection], from view: PlatformView?, trailing: Bool = false) {
        guard let rect = rect(of: view) else { return }
        open(Shown(sections: sections, anchor: rect, trailing: trailing, atPoint: false))
    }

    /// Opens a menu at a point in a view (right-click).
    func present(_ sections: [BXMenuSection], at point: CGPoint, in view: PlatformView) {
        guard let host = hostRef.view else { return }
        let r = Self.convert(CGRect(origin: point, size: .zero), from: view, to: host)
        open(Shown(sections: sections, anchor: r, trailing: false, atPoint: true))
    }

    func close(then action: (@MainActor () -> Void)? = nil) {
        withAnimation(.easeOut(duration: 0.12)) { shown = nil }
        if let action { DispatchQueue.main.async { action() } }
    }

    func share(_ url: URL) {
        guard let host = hostRef.view else { return }
        #if os(macOS)
        let picker = NSSharingServicePicker(items: [url])
        // NSView coordinates (bottom-left origin unless flipped).
        let r = host.isFlipped ? shareRect : CGRect(x: shareRect.minX, y: host.bounds.height - shareRect.maxY, width: max(shareRect.width, 1), height: max(shareRect.height, 1))
        picker.show(relativeTo: r, of: host, preferredEdge: .minY)
        #else
        guard var top = host.window?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = host
        sheet.popoverPresentationController?.sourceRect = shareRect
        top.present(sheet, animated: true)
        #endif
    }

    private func open(_ s: Shown) {
        shareRect = s.anchor
        dialog = nil
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) { shown = s }
    }

    private func rect(of view: PlatformView?) -> CGRect? {
        guard let view, let host = hostRef.view else { return nil }
        return Self.convert(view.bounds, from: view, to: host)
    }

    /// A rect in `view` as the host's top-left-origin coordinates.
    static func convert(_ rect: CGRect, from view: PlatformView, to host: PlatformView) -> CGRect {
        let r = view.convert(rect, to: host)
        #if os(macOS)
        return host.isFlipped ? r : CGRect(x: r.minX, y: host.bounds.height - r.maxY, width: r.width, height: r.height)
        #else
        return r
        #endif
    }
}

/// Holds a platform view weakly, for converting frames when a menu opens (no per-frame geometry work).
final class ViewRef {
    weak var view: PlatformView?
}

/// An invisible platform view that records itself in a `ViewRef` and lets every touch and click through.
struct ViewCatcher {
    let ref: ViewRef
}

#if os(macOS)
private final class PassthroughNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
extension ViewCatcher: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { let v = PassthroughNSView(); ref.view = v; return v }
    func updateNSView(_ v: NSView, context: Context) { ref.view = v }
}
#else
extension ViewCatcher: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { let v = UIView(); v.isUserInteractionEnabled = false; ref.view = v; return v }
    func updateUIView(_ v: UIView, context: Context) { ref.view = v }
}
#endif

extension View {
    /// Draws Boxtube menus and dialogs opened anywhere inside this view. Put one at the root of each
    /// window, sheet and full-screen cover.
    func bxMenuHost() -> some View { modifier(BXMenuHostModifier()) }
}

private struct BXMenuHostModifier: ViewModifier {
    @State private var host = BXMenuHost()

    func body(content: Content) -> some View {
        content
            .environment(host)
            .overlay {
                ZStack(alignment: .topLeading) {
                    ViewCatcher(ref: host.hostRef).allowsHitTesting(false)
                    if let shown = host.shown {
                        BXMenuLayer(shown: shown, host: host).id(shown.id)
                    }
                    if let dialog = host.dialog {
                        BXDialogLayer(dialog: dialog, host: host).id(dialog.id)
                    }
                }
                .ignoresSafeArea()
            }
    }
}

// MARK: - Triggers

/// A button that opens a Boxtube menu (the ⋯ buttons, speed, playlist and sort chips).
struct BXMenuButton<Label: View>: View {
    @Environment(BXMenuHost.self) private var host: BXMenuHost?
    var trailing = false
    var sections: () -> [BXMenuSection]
    var label: Label
    @State private var anchor = ViewRef()

    init(trailing: Bool = false, @BXMenuBuilder sections: @escaping () -> [BXMenuSection], @ViewBuilder label: () -> Label) {
        self.trailing = trailing
        self.sections = sections
        self.label = label()
    }

    var body: some View {
        Button {
            host?.present(sections(), from: anchor.view, trailing: trailing)
        } label: {
            label.background(ViewCatcher(ref: anchor))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Boxtube's menu on right-click (Mac) or long press (iPhone), in place of `.contextMenu`.
    func bxContextMenu(@BXMenuBuilder _ sections: @escaping () -> [BXMenuSection]) -> some View {
        modifier(BXContextMenu(sections: sections))
    }
}

private struct BXContextMenu: ViewModifier {
    @Environment(BXMenuHost.self) private var host: BXMenuHost?
    var sections: () -> [BXMenuSection]
    @State private var anchor = ViewRef()

    func body(content: Content) -> some View {
        #if os(macOS)
        content.overlay(RightClickCatcher { point, view in host?.present(sections(), at: point, in: view) })
        #else
        content
            .background(ViewCatcher(ref: anchor))
            .gesture(BXLongPress {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                host?.present(sections(), from: anchor.view)
            })
        #endif
    }
}

#if os(macOS)
/// Catches right-clicks (and control-clicks) only; every other click and hover goes to the view beneath.
private struct RightClickCatcher: NSViewRepresentable {
    var onRightClick: (CGPoint, NSView) -> Void

    final class CatcherView: NSView {
        var onRightClick: ((CGPoint, NSView) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent else { return nil }
            let right = e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
            return right ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { fire(event) }
        override func mouseDown(with event: NSEvent) { fire(event) }
        private func fire(_ event: NSEvent) {
            onRightClick?(convert(event.locationInWindow, from: nil), self)
        }
    }

    func makeNSView(context: Context) -> CatcherView { let v = CatcherView(); v.onRightClick = onRightClick; return v }
    func updateNSView(_ v: CatcherView, context: Context) { v.onRightClick = onRightClick }
}
#else
/// A UIKit long press, so the button under the finger is cancelled instead of tapped when it fires.
private struct BXLongPress: UIGestureRecognizerRepresentable {
    var action: () -> Void
    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = 0.4
        return g
    }
    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.state == .began { action() }
    }
}
#endif

// MARK: - The menu itself

private enum MenuMetrics {
    #if os(macOS)
    static let row: CGFloat = 34, tile: CGFloat = 24, tileRadius: CGFloat = 7, rowRadius: CGFloat = 8
    static let font: CGFloat = 13.5, iconFont: CGFloat = 12, radius: CGFloat = 14, pad: CGFloat = 6
    static let minWidth: CGFloat = 220, maxWidth: CGFloat = 320
    #else
    static let row: CGFloat = 46, tile: CGFloat = 30, tileRadius: CGFloat = 9, rowRadius: CGFloat = 12
    static let font: CGFloat = 15, iconFont: CGFloat = 14, radius: CGFloat = 22, pad: CGFloat = 8
    static let minWidth: CGFloat = 250, maxWidth: CGFloat = 320
    #endif
}

/// Positions the panel by its trigger and catches clicks outside it.
private struct BXMenuLayer: View {
    let shown: BXMenuHost.Shown
    let host: BXMenuHost
    @State private var size: CGSize?
    @State private var above: Bool?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(dim)
                    .contentShape(Rectangle())
                    .onTapGesture { host.close() }
                    #if os(macOS)
                    .simultaneousGesture(TapGesture().modifiers(.control).onEnded { host.close() })
                    #endif
                    .accessibilityLabel("Close menu")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { host.close() }
                BXMenuPanel(sections: shown.sections, host: host, maxHeight: max(geo.size.height - 100, 160))
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .offset(origin(in: geo.size))
                    .opacity(size == nil ? 0 : 1)
                    .transition(.scale(scale: 0.94, anchor: (above ?? false) ? .bottom : .top).combined(with: .opacity))
            }
        }
    }

    private var dim: Double {
        #if os(macOS)
        0.001
        #else
        0.18
        #endif
    }

    private func origin(in bounds: CGSize) -> CGSize {
        guard let size else { return CGSize(width: shown.anchor.minX, height: shown.anchor.maxY) }
        let margin: CGFloat = 10, gap: CGFloat = 6
        let a = shown.anchor
        var x = shown.trailing ? a.maxX - size.width : a.minX
        x = min(max(x, margin), bounds.width - size.width - margin)
        let topInset: CGFloat = 50, bottomInset: CGFloat = 30
        let fitsBelow = a.maxY + gap + size.height <= bounds.height - bottomInset
        let fitsAbove = a.minY - gap - size.height >= topInset
        // Decide once, so moving into a submenu doesn't flip the panel to the other side.
        let goAbove = above ?? (!fitsBelow && fitsAbove)
        if above == nil { DispatchQueue.main.async { above = goAbove } }
        var y = goAbove ? a.minY - gap - size.height : a.maxY + gap
        y = min(max(y, topInset), bounds.height - size.height - bottomInset)
        return CGSize(width: x, height: y)
    }
}

/// The panel: sections of rows, with submenus opening in place behind a back row.
struct BXMenuPanel: View {
    let sections: [BXMenuSection]
    let host: BXMenuHost
    /// Taller pages scroll inside the panel instead of running off the window.
    var maxHeight: CGFloat = .infinity
    @State private var contentHeight: CGFloat?
    @State private var stack: [(title: String, sections: [BXMenuSection])] = []
    @State private var highlighted: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        let page = stack.last?.sections ?? sections
        VStack(alignment: .leading, spacing: 0) {
            if let title = stack.last?.title {
                Button { back() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left").font(.system(size: MenuMetrics.iconFont, weight: .bold))
                        Text(title).font(.system(size: MenuMetrics.font, weight: .bold)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(BX.text)
                    .padding(.horizontal, 10).frame(height: MenuMetrics.row)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                divider
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(page.enumerated()), id: \.element.id) { i, section in
                        if i > 0, !section.items.isEmpty { divider }
                        if let title = section.title {
                            Text(title.uppercased())
                                .font(.system(size: 11, weight: .bold)).kerning(0.88)
                                .foregroundStyle(Color(hex: 0x8A8A93))
                                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(section.items) { item in row(item) }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.automatic)
            .frame(height: min(contentHeight ?? 0, maxHeight - (stack.isEmpty ? 0 : MenuMetrics.row + 9) - MenuMetrics.pad * 2))
        }
        .padding(MenuMetrics.pad)
        .frame(minWidth: MenuMetrics.minWidth, maxWidth: MenuMetrics.maxWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: MenuMetrics.radius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: MenuMetrics.radius, style: .continuous).fill(Color(hex: 0x18181C, opacity: 0.86)))
        }
        .overlay(RoundedRectangle(cornerRadius: MenuMetrics.radius, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .clipShape(.rect(cornerRadius: MenuMetrics.radius, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.escape) { if stack.isEmpty { host.close() } else { back() }; return .handled }
        .onKeyPress(.downArrow) { move(1, in: page); return .handled }
        .onKeyPress(.upArrow) { move(-1, in: page); return .handled }
        .onKeyPress(.leftArrow) { if stack.isEmpty { return .ignored }; back(); return .handled }
        .onKeyPress(.rightArrow) {
            if let item = current(in: page), case .submenu = item.kind { run(item); return .handled }
            return .ignored
        }
        .onKeyPress(.return) { if let item = current(in: page) { run(item) }; return .handled }
        .onKeyPress(.space) { if let item = current(in: page) { run(item) }; return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 4)
    }

    @ViewBuilder
    private func row(_ item: BXMenuItem) -> some View {
        let isNote: Bool = { if case .note = item.kind { return true } else { return false } }()
        let isSubmenu: Bool = { if case .submenu = item.kind { return true } else { return false } }()
        let tint = item.destructive ? BX.coralText : (item.tint ?? BX.text2)
        let content = HStack(spacing: 10) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: MenuMetrics.iconFont, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: MenuMetrics.tile, height: MenuMetrics.tile)
                    .background((item.destructive || item.tint != nil ? tint : Color.white).opacity(item.destructive || item.tint != nil ? 0.16 : 0.07),
                                in: .rect(cornerRadius: MenuMetrics.tileRadius, style: .continuous))
            }
            Text(item.title)
                .font(.system(size: isNote ? MenuMetrics.font - 1.5 : MenuMetrics.font, weight: isNote ? .medium : .semibold))
                .foregroundStyle(item.destructive ? BX.coralText : (isNote ? tint : BX.text))
                .lineLimit(isNote ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if let detail = item.detail {
                Text(detail).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color(hex: 0xA1A1AA)).lineLimit(1)
            }
            if item.checked {
                Image(systemName: "checkmark").font(.system(size: MenuMetrics.iconFont, weight: .bold)).foregroundStyle(BX.coralText)
            }
            if isSubmenu {
                Image(systemName: "chevron.right").font(.system(size: MenuMetrics.iconFont - 1, weight: .bold)).foregroundStyle(Color(hex: 0x8A8A93))
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: MenuMetrics.row)
        .background(highlighted == item.id && item.isActionable ? Color.white.opacity(0.08) : .clear,
                    in: .rect(cornerRadius: MenuMetrics.rowRadius, style: .continuous))
        .contentShape(.rect(cornerRadius: MenuMetrics.rowRadius))
        .opacity(item.disabled ? 0.4 : 1)

        if isNote {
            content.accessibilityElement(children: .combine)
        } else {
            Button { run(item) } label: { content }
                .buttonStyle(MenuRowStyle(onPress: { highlighted = item.id }))
                .disabled(item.disabled)
                .onHover { inside in if inside { highlighted = item.id } else if highlighted == item.id { highlighted = nil } }
                .accessibilityAddTraits(item.checked ? .isSelected : [])
        }
    }

    private func current(in page: [BXMenuSection]) -> BXMenuItem? {
        page.flatMap(\.items).first { $0.id == highlighted && $0.isActionable }
    }

    private func move(_ step: Int, in page: [BXMenuSection]) {
        let items = page.flatMap(\.items).filter(\.isActionable)
        guard !items.isEmpty else { return }
        let i = items.firstIndex { $0.id == highlighted } ?? (step > 0 ? -1 : items.count)
        highlighted = items[(i + step + items.count) % items.count].id
    }

    private func back() {
        withAnimation(.easeOut(duration: 0.15)) { _ = stack.popLast() }
        highlighted = nil
    }

    private func run(_ item: BXMenuItem) {
        guard item.isActionable else { return }
        switch item.kind {
        case .action(let action): host.close(then: action)
        case .submenu(let sections):
            withAnimation(.easeOut(duration: 0.15)) { stack.append((item.title, sections)) }
            highlighted = nil
        case .share(let url): host.close { host.share(url) }
        case .note: break
        }
    }
}

/// Highlights a row while it's pressed (touch), like hover does on Mac.
private struct MenuRowStyle: ButtonStyle {
    var onPress: () -> Void
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { onPress() } }
    }
}
