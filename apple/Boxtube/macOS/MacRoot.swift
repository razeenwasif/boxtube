import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

enum MacSection: Hashable {
    case home, shorts, explore, subscriptions, playlists, watchLater, history, liked, notes, music, timeBox
    case channel(String)
}

struct MacRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @State private var section: MacSection? = .home
    @State private var subs: [Q.SubscriptionRow] = []
    @State private var laterCount = 0
    @State private var showPalette = false
    @State private var showShortcuts = false

    @State private var sidebarVisible = true

    var body: some View {
        @Bindable var model = model
        let chrome = currentChrome
        HStack(spacing: 0) {
            switch chrome {
            case .sidebar:
                MacSidebar(section: $section, subs: subs, laterCount: laterCount) {
                    withAnimation(.snappy(duration: 0.3)) { sidebarVisible = false }
                }
                .frame(width: 248)
                .background(Color(hex: 0x141417))
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
                .padding(.leading, 10).padding(.vertical, 10)
                .transition(.move(edge: .leading).combined(with: .opacity))
            case .rail:
                MacRail(section: $section)
                    .padding(.leading, 10).padding(.vertical, 10)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .hidden, .music:
                EmptyView()
            }
            VStack(spacing: 0) {
                if chrome != .music, !(chrome == .rail && model.showNotes) { topBar(chrome) }
                NavigationStack(path: Binding(get: { model.paths[.home] ?? [] }, set: { model.paths[.home] = $0 })) {
                    detail
                        .navigationDestination(for: Route.self) {
                            // Opaque, or the screen underneath shows through on macOS.
                            MacRouteScreen(route: $0).navigationBarBackButtonHidden(true)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(background)
                        }
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: chrome)
        .background(background)
        .ignoresSafeArea(edges: .top)
        .background(TrafficLightPositioner(centers: lightCenters(chrome)).frame(width: 0, height: 0))
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .overlay {
            if showPalette { MacCommandPalette(isPresented: $showPalette, section: $section) }
        }
        .overlay {
            // Leaving a playing video keeps it on screen, snapped to a corner.
            if model.watching == nil, model.player.video != nil, section != .music, !showPalette {
                MacMiniPlayer()
            }
        }
        .animation(.snappy(duration: 0.3), value: model.watching == nil && model.player.video != nil)
        .overlay(alignment: .bottom) {
            if showShortcuts { ShortcutHUD().padding(.bottom, 24).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast { Toast(text: toast).padding(.top, 12) }
        }
        .sheet(isPresented: $model.showTimeBox) { TimeBoxView().frame(width: 460, height: 760) }
        .background { PlaybackTicker() }
        .onAppear { model.openWindowAction = { [openWindow] id in openWindow(id: id) } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.preview.stop() } else { model.scheduleSync() } }
        .onChange(of: section) { _, s in
            model.watching = nil
            model.paths[.home] = []
            if s == .music { model.mode = .music } else if s == .home { model.mode = .videos }
        }
        .onReceive(NotificationCenter.default.publisher(for: .boxtubeShowShortcuts)) { _ in withAnimation(.snappy) { showShortcuts.toggle() } }
        .onReceive(NotificationCenter.default.publisher(for: .boxtubeShowPalette)) { _ in showPalette = true }
        .observing(model.store, { db in try Q.subscriptions(db) }) { subs = $0 }
        .observing(model.store, { db in try WatchLaterEntry.fetchCount(db) }) { laterCount = $0 }
    }

    enum Chrome: Equatable { case sidebar, hidden, rail, music }

    private var currentChrome: Chrome {
        if model.watching != nil { return .rail }
        if section == .music { return .music }
        return sidebarVisible ? .sidebar : .hidden
    }

    /// Button centres from the window's top-left, matching each artboard.
    private func lightCenters(_ chrome: Chrome) -> [CGPoint] {
        switch chrome {
        case .sidebar: return (0..<3).map { CGPoint(x: 35 + 20 * Double($0), y: 38) }
        case .hidden: return (0..<3).map { CGPoint(x: 29 + 20 * Double($0), y: 40) }
        case .rail: return (0..<3).map { CGPoint(x: 42, y: 32 + 19 * Double($0)) }
        case .music: return (0..<3).map { CGPoint(x: 30 + 20 * Double($0), y: 37) }
        }
    }

    // MARK: Top bar (back/forward, centred search, bell) — doubles as the window drag area

    private func topBar(_ chrome: Chrome) -> some View {
        ZStack {
            HStack(spacing: 6) {
                if chrome == .hidden {
                    Color.clear.frame(width: 72, height: 1)
                    barButton("sidebar.left", "Show sidebar") { withAnimation(.snappy(duration: 0.3)) { sidebarVisible = true } }
                }
                barButton("chevron.left", "Back", disabled: model.watching == nil && (model.paths[.home] ?? []).isEmpty) { goBack() }
                barButton("chevron.right", "Forward", disabled: true) {}
                Spacer()
                if chrome == .rail, model.tintFromVideo, model.palette != .standard { PalettePill() }
                MacCastButton()
                Button { section = .subscriptions } label: {
                    Image(systemName: "bell").font(.system(size: 15, weight: .medium)).foregroundStyle(BX.text2)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                        .overlay(alignment: .topTrailing) {
                            if subs.contains(where: { $0.newCount > 0 }), !model.calmMode {
                                Circle().fill(BX.coral).frame(width: 8, height: 8)
                                    .overlay(Circle().strokeBorder(BX.ground, lineWidth: 2)).offset(x: -8, y: 7)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("New from subscriptions")
                .accessibilityLabel("Notifications")
            }
            Button { showPalette = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundStyle(BX.dim)
                    Text("Search videos, channels and playlists").foregroundStyle(BX.dim)
                    Spacer()
                    Text("⌘K").font(.system(size: 11.5, weight: .medium)).foregroundStyle(BX.muted)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Color(hex: 0x232327), in: .rect(cornerRadius: 6))
                }
                .font(.system(size: 13.5))
                .padding(.leading, 14).padding(.trailing, 8)
                .frame(height: 38)
                .frame(maxWidth: 520)
                .background(Color(hex: 0x17171A), in: .rect(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(BX.line))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)
            // Keep clear of the buttons on either side when the window is narrow.
            .padding(.horizontal, chrome == .rail && model.tintFromVideo && model.palette != .standard ? 380 : (chrome == .hidden ? 160 : 110))
        }
        .padding(.leading, 20).padding(.trailing, 24)
        .frame(height: 60)
        .padding(.top, 10)
        .background(Color.black.opacity(0.001))
        .gesture(WindowDragGesture())
    }

    private func barButton(_ icon: String, _ label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(disabled ? Color(hex: 0x5A5A63) : BX.text2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private func goBack() {
        if model.watching != nil { model.watching = nil }
        else if !(model.paths[.home] ?? []).isEmpty { model.paths[.home]?.removeLast() }
    }

    private var background: Color {
        model.watching != nil && model.tintFromVideo ? model.palette.ground : (model.calmMode ? BX.calmGround : BX.ground)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let video = model.watching {
            MacWatchView(video: video)
        } else {
            switch section ?? .home {
            case .home: model.calmMode ? AnyView(MacCalmHome()) : AnyView(MacHome())
            case .shorts: MacShorts()
            case .explore: MacExplore()
            case .subscriptions: MacSubscriptions()
            case .playlists: MacPlaylists()
            case .watchLater: MacWatchLater()
            case .history: MacVideoGrid(title: "History", fetch: { db in try Q.history(db, limit: 120).map(\.video) })
            case .liked: MacVideoGrid(title: "Liked videos", fetch: { db in try Q.liked(db) })
            case .notes: MacAllNotes()
            case .music: MacMusic(onVideos: { section = .home })
            case .timeBox: TimeBoxView().frame(maxWidth: 520).frame(maxWidth: .infinity)
            case .channel(let id): MacChannel(channelId: id)
            }
        }
    }
}

// MARK: - Sidebar (macOS · Home mockup)

struct MacSidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var section: MacSection?
    var subs: [Q.SubscriptionRow]
    var laterCount: Int
    var onHide: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    Button(action: onHide) {
                        Image(systemName: "sidebar.left").font(.system(size: 15, weight: .medium)).foregroundStyle(BX.muted)
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Hide sidebar")
                    .accessibilityLabel("Hide sidebar")
                }
                .frame(height: 28)
                .padding(.horizontal, 4)
                .background(Color.black.opacity(0.001))
                .gesture(WindowDragGesture())
                HStack(spacing: 10) {
                    BrandMark(size: 30)
                    Text("Boxtube").font(BX.display(21)).kerning(-0.4)
                }
                .padding(.horizontal, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Boxtube")

                VStack(alignment: .leading, spacing: 2) {
                    row(.home, "Home", "house")
                    row(.shorts, "Shorts", "play.rectangle.on.rectangle")
                    row(.explore, "Explore", "safari")
                    row(.music, "Music", "music.note")
                }

                VStack(alignment: .leading, spacing: 2) {
                    header("Library")
                    row(.subscriptions, "Subscriptions", "rectangle.stack.badge.play") {
                        if subs.contains(where: { $0.newCount > 0 }) { Circle().fill(BX.coral).frame(width: 7, height: 7).accessibilityLabel("New videos") }
                    }
                    row(.playlists, "Playlists", "music.note.list")
                    row(.watchLater, "Watch later", "clock") {
                        if laterCount > 0 { Text("\(laterCount)").font(.system(size: 12)).foregroundStyle(BX.dim) }
                    }
                    row(.history, "History", "clock.arrow.circlepath")
                    row(.liked, "Liked videos", "heart")
                    row(.notes, "Notes", "note.text")
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        header("Subscriptions")
                        Spacer()
                        Button("See all") { section = .subscriptions }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(BX.coralText)
                            .padding(.trailing, 10)
                    }
                    ForEach(subs.prefix(10)) { s in
                        row(.channel(s.channel.id), s.channel.title, nil, avatar: s.channel) {
                            if s.isLive {
                                Text("LIVE").font(.system(size: 10, weight: .bold)).kerning(0.4).foregroundStyle(BX.coralInk)
                                    .padding(.horizontal, 5).padding(.vertical, 2).background(BX.coral, in: .rect(cornerRadius: 4))
                            } else if s.newCount > 0 {
                                Circle().fill(BX.coral).frame(width: 7, height: 7).accessibilityLabel("New videos")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                MyAvatar(size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.displayName).font(.system(size: 13, weight: .semibold))
                    Text(model.calmMode ? "Calm mode on" : (model.account?.email ?? "@\(model.displayName.lowercased().replacingOccurrences(of: " ", with: ""))"))
                        .font(.system(size: 12)).foregroundStyle(model.calmMode ? BX.sageText : BX.dim)
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 15)).foregroundStyle(BX.muted).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14)
            .background(Color(hex: 0x141417))
            .overlay(alignment: .top) { Rectangle().fill(BX.line).frame(height: 1).padding(.horizontal, 12) }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold)).kerning(0.6)
            .foregroundStyle(BX.dim)
            .padding(.horizontal, 10).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ target: MacSection, _ title: String, _ icon: String?, avatar: Channel? = nil) -> some View {
        row(target, title, icon, avatar: avatar) { EmptyView() }
    }

    private func row<Trailing: View>(_ target: MacSection, _ title: String, _ icon: String?, avatar: Channel? = nil, @ViewBuilder trailing: () -> Trailing) -> some View {
        let active = section == target
        return Button { section = target } label: {
            HStack(spacing: 11) {
                if let avatar {
                    ChannelAvatar(title: avatar.title, url: avatar.avatarURL, size: 22)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(active ? BX.coralText : BX.muted)
                        .frame(width: 20)
                }
                Text(title)
                    .font(.system(size: 13.5, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? BX.coralText : BX.text2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                trailing()
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(active ? BX.coral.opacity(0.14) : .clear, in: .rect(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowStyle())
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct SidebarRowStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        HoverHighlight(pressed: configuration.isPressed) { configuration.label }
    }
}

struct HoverHighlight<Content: View>: View {
    var pressed: Bool
    var radius: CGFloat = 9
    @ViewBuilder var content: Content
    @State private var hovering = false
    var body: some View {
        content
            .background(hovering || pressed ? Color.white.opacity(0.05) : .clear, in: .rect(cornerRadius: radius))
            .onHover { hovering = $0 }
    }
}

// MARK: - Icon rail (macOS · Watch / Notes / Colours artboards)

struct MacRail: View {
    @Environment(AppModel.self) private var model
    @Binding var section: MacSection?

    var body: some View {
        let tinted = model.tintFromVideo && model.palette != .standard
        let fg = tinted ? model.palette.muted : BX.text2
        VStack(spacing: 6) {
            Color.clear.frame(height: 50 + 14) // traffic lights sit here (12 pt, 7 pt apart)
            item(.home, "Home", fg) { go(.home) }
            item(.shorts, "Shorts", fg) { go(.shorts) }
            item(.subs, "Subscriptions", fg) { go(.subscriptions) }
            item(.playlists, "Playlists", fg) { go(.playlists) }
            item(.history, "History", fg) { go(.history) }
            Button { withAnimation(.snappy) { model.showNotes.toggle() } } label: {
                Image(systemName: "doc.text").font(.system(size: 17, weight: .regular))
                    .foregroundStyle(model.showNotes ? BX.coralText : fg)
                    .frame(width: 42, height: 42)
                    .background(model.showNotes ? BX.coral.opacity(0.14) : .clear, in: .rect(cornerRadius: 11))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Notes (N)")
            .accessibilityLabel("Notes")
            .accessibilityAddTraits(model.showNotes ? .isSelected : [])
            Spacer()
            MyAvatar(size: 32).accessibilityLabel(model.displayName)
        }
        .padding(.top, 16).padding(.bottom, 16)
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background(tinted ? model.palette.surface : Color(hex: 0x141417))
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }

    private func go(_ s: MacSection) {
        model.showNotes = false
        model.watching = nil
        model.paths[.home] = []
        section = s
    }


    private func item(_ icon: BXIcon, _ label: String, _ fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconView(icon, size: 20, lineWidth: 1.8).foregroundStyle(fg)
                .frame(width: 42, height: 42).contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Toolbar pill from the colours-from-video artboard: label, three swatches, on/off switch.
struct PalettePill: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let p = model.palette
        HStack(spacing: 10) {
            Text("Palette from this video").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.muted)
            HStack(spacing: 4) {
                ForEach(Array(p.swatches.enumerated()), id: \.offset) { _, c in
                    Circle().fill(c).frame(width: 18, height: 18).overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1.5))
                }
            }
            .accessibilityHidden(true)
            Button {
                withAnimation(.easeInOut(duration: 0.4)) { model.tintFromVideo = false; model.palette = .standard }
            } label: {
                Capsule().fill(p.accent).frame(width: 38, height: 24)
                    .overlay(alignment: .trailing) { Circle().fill(p.ground).frame(width: 18, height: 18).padding(.trailing, 3) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tint the window from the video")
            .accessibilityValue("On")
        }
        .padding(.leading, 12).padding(.trailing, 6)
        .frame(height: 36)
        .background(p.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
    }
}

struct MacRouteScreen: View {
    var route: Route
    var body: some View {
        switch route {
        case .channel(let id): MacChannel(channelId: id)
        case .playlist(let id): MacVideoGrid(title: "Playlist", playlistId: id, fetch: { db in try Q.playlistVideos(db, id: id) })
        case .watchLater: MacWatchLater()
        case .liked: MacVideoGrid(title: "Liked videos", fetch: { db in try Q.liked(db) })
        case .history: MacVideoGrid(title: "History", fetch: { db in try Q.history(db, limit: 120).map(\.video) })
        case .search(let q): MacSearch(query: q)
        case .musicLibrary: MacMusic()
        }
    }
}

extension Notification.Name {
    static let boxtubeShowShortcuts = Notification.Name("boxtube.showShortcuts")
    static let boxtubeShowPalette = Notification.Name("boxtube.showPalette")
}
