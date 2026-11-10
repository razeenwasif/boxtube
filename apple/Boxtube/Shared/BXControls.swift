import SwiftUI
import BoxtubeCore
import BoxtubeUI

// Boxtube's buttons, switch, dropdown chip, dialog and settings rows, in place of the system's.
// Values come from the artboards: coral and dark pills (Watch later, Watch), chips (Playlists' "Recent ▾"),
// the Calm and Autoplay switches, and the palette for dialogs.

// MARK: - Buttons

enum BXButtonKind {
    /// Coral, for the main action (Play, Create, Review).
    case primary
    /// Dark, for everything beside it (Keep all, Cancel).
    case secondary
    /// Light, like Subscribe.
    case light
    /// Dark with coral text, for actions that remove things.
    case destructive
    /// Sage, for Calm mode.
    case calm
}

struct BXButtonStyle: ButtonStyle {
    var kind: BXButtonKind = .secondary
    var height: CGFloat = 36
    var fullWidth = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        let (bg, fg): (Color, Color) = switch kind {
        case .primary: (BX.coral, BX.coralInk)
        case .secondary: (Color(hex: 0x222227), BX.text)
        case .light: (BX.text, BX.ground)
        case .destructive: (Color(hex: 0x222227), BX.coralText)
        case .calm: (Color(hex: 0x9DB39A, opacity: 0.16), BX.sageText)
        }
        configuration.label
            .font(.system(size: height >= 40 ? 14.5 : 13.5, weight: kind == .primary || kind == .light ? .bold : .semibold))
            .lineLimit(1)
            .foregroundStyle(fg)
            .padding(.horizontal, height * 0.42)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(bg, in: Capsule())
            .overlay { if kind == .calm { Capsule().strokeBorder(Color(hex: 0x9DB39A, opacity: 0.4)) } }
            .contentShape(Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BXButtonStyle {
    static func bx(_ kind: BXButtonKind = .secondary, height: CGFloat = 36, fullWidth: Bool = false) -> BXButtonStyle {
        BXButtonStyle(kind: kind, height: height, fullWidth: fullWidth)
    }
}

/// The chip that opens a choice menu: "Clears after 4 weeks ▾", "Recent ▾".
struct BXDropdownChip: View {
    var title: String
    var icon: String? = nil
    var height: CGFloat = 32

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 12.5, weight: .semibold)) }
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 10.5, weight: .bold)).foregroundStyle(BX.muted)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(BX.text2)
        .padding(.horizontal, 12).frame(height: height)
        .background(BX.surface2, in: Capsule())
        .contentShape(Capsule())
    }
}

/// A chip that picks one of several values from a Boxtube menu (in place of `Picker`).
struct BXPicker<T: Hashable & Sendable>: View {
    var options: [T]
    @Binding var selection: T
    var title: (T) -> String
    var icon: String? = nil
    var label: ((T) -> String)? = nil

    var body: some View {
        BXMenuButton(trailing: true) {
            bxChoices(options, selected: selection, title: title) { selection = $0 }
        } label: {
            BXDropdownChip(title: (label ?? title)(selection), icon: icon)
        }
        .accessibilityValue(title(selection))
    }
}

// MARK: - Switch

/// The artboards' switch: a 34×22 track in the accent colour with a dark knob.
struct BXToggleStyle: ToggleStyle {
    var tint: Color = BX.coral
    /// Pushes the switch to the trailing edge (settings rows); off for a label and switch side by side.
    var stretch = true
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label.frame(maxWidth: stretch ? .infinity : nil, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? tint : Color.white.opacity(0.14))
                    Circle()
                        .fill(configuration.isOn ? Color(hex: 0x101014) : Color(hex: 0xC9C9CF))
                        .padding(2)
                }
                .frame(width: 38, height: 24)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

extension ToggleStyle where Self == BXToggleStyle {
    static var bx: BXToggleStyle { BXToggleStyle() }
    static func bx(tint: Color) -> BXToggleStyle { BXToggleStyle(tint: tint) }
}

// MARK: - Settings rows

/// A titled card of rows, like the You tab's list: dark, rounded, hairlines between rows.
struct BXCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.footer = footer; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold)).kerning(0.88)
                    .foregroundStyle(Color(hex: 0x8A8A93))
                    .padding(.horizontal, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        row
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .overlay(alignment: .top) {
                                if i > 0 { Rectangle().fill(.white.opacity(0.06)).frame(height: 1).padding(.leading, 14) }
                            }
                    }
                }
            }
            .background(Color(hex: 0x151518), in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.06)))
            if let footer {
                Text(footer).font(.system(size: 12)).foregroundStyle(BX.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }
}

/// Title (and optional subtitle) on the left, any control on the right.
struct BXRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var titleColor: Color = BX.text
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, titleColor: Color = BX.text, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.titleColor = titleColor; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            BXRowLabel(title: title, subtitle: subtitle, color: titleColor)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension BXRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, titleColor: Color = BX.text) {
        self.init(title, subtitle: subtitle, titleColor: titleColor) { EmptyView() }
    }
}

struct BXRowLabel: View {
    var title: String
    var subtitle: String?
    var color: Color = BX.text
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14.5, weight: .medium)).foregroundStyle(color)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 12)).foregroundStyle(BX.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A row that is itself a button (Sign out, Clear watch history…).
struct BXActionRow: View {
    var title: String
    var subtitle: String?
    var icon: String?
    var destructive = false
    var busy = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(destructive ? BX.coralText : BX.text2)
                        .frame(width: 30, height: 30)
                        .background((destructive ? BX.coral : Color.white).opacity(destructive ? 0.16 : 0.07), in: .rect(cornerRadius: 9))
                }
                BXRowLabel(title: title, subtitle: subtitle, color: destructive ? BX.coralText : BX.text)
                Spacer(minLength: 8)
                if busy { ProgressView().controlSize(.small) } else { Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: 0x5A5A63)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

/// A text field styled like the command panel's search field.
struct BXTextField: View {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium))
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 14).frame(height: 44)
            .background(Color(hex: 0x0F0F12), in: .rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(focused ? BX.coral.opacity(0.6) : .white.opacity(0.1), lineWidth: 1.5))
    }
}

// MARK: - Dialog

/// A Boxtube dialog: title, message, an optional text field, and pill buttons (in place of alerts and
/// confirmation sheets). Shown by the nearest `bxMenuHost()`.
struct BXDialog: Identifiable {
    struct Action {
        var title: String
        var kind: BXButtonKind = .secondary
        var run: @MainActor (String) -> Void = { _ in }
    }

    let id = UUID()
    var title: String
    var message: String?
    var field: (placeholder: String, initial: String)?
    var actions: [Action]
    /// What closing without choosing does (tapping outside, Esc).
    var cancel: @MainActor () -> Void = {}

    static func confirm(_ title: String, message: String? = nil, actions: [Action], cancel: @escaping @MainActor () -> Void = {}) -> BXDialog {
        BXDialog(title: title, message: message, field: nil, actions: actions + [Action(title: "Cancel", run: { _ in cancel() })], cancel: cancel)
    }

    static func prompt(_ title: String, placeholder: String, initial: String = "", confirm: String,
                       run: @escaping @MainActor (String) -> Void) -> BXDialog {
        BXDialog(title: title, message: nil, field: (placeholder, initial),
                 actions: [Action(title: confirm, kind: .primary, run: run), Action(title: "Cancel")])
    }
}

extension BXMenuHost {
    func show(_ dialog: BXDialog) {
        shown = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { self.dialog = dialog }
    }

    func dismissDialog(then action: (@MainActor () -> Void)? = nil) {
        withAnimation(.easeOut(duration: 0.14)) { dialog = nil }
        if let action { DispatchQueue.main.async { action() } }
    }
}

struct BXDialogLayer: View {
    let dialog: BXDialog
    let host: BXMenuHost
    @State private var text = ""
    @State private var shown = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.45))
                .background(.ultraThinMaterial.opacity(0.6))
                .opacity(shown ? 1 : 0)
                .onTapGesture { cancel() }
                .accessibilityHidden(true)
            if shown {
                card
                    .padding(.horizontal, 24)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            text = dialog.field?.initial ?? ""
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { shown = true }
        }
    }

    private var card: some View {
        let stacked = dialog.actions.count > 2
        return VStack(alignment: .leading, spacing: 14) {
            Text(dialog.title).font(.system(size: 17, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message = dialog.message {
                Text(message).font(.system(size: 13.5)).foregroundStyle(BX.text2).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let field = dialog.field {
                BXTextField(placeholder: field.placeholder, text: $text) { choose(dialog.actions[0]) }
                    .focused($focused)
                    .onAppear { focused = true }
            }
            let buttons = ForEach(Array(dialog.actions.enumerated()), id: \.offset) { _, a in
                Button(a.title) { choose(a) }
                    .buttonStyle(.bx(a.kind, height: 40, fullWidth: true))
                    .keyboardShortcut(a.kind == .primary ? .defaultAction : (a.title == "Cancel" ? .cancelAction : nil))
            }
            if stacked {
                VStack(spacing: 8) { buttons }.padding(.top, 4)
            } else {
                HStack(spacing: 10) { buttons }.padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: 380, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(hex: 0x18181C, opacity: 0.92)))
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
        .onKeyPress(.escape) { cancel(); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func choose(_ action: BXDialog.Action) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        host.dismissDialog { action.run(value) }
    }

    private func cancel() {
        host.dismissDialog { dialog.cancel() }
    }
}
