import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

// MARK: - Menu commands (⌘ shortcuts; single-key J/K/L live on the watch page)

struct MacCommands: Commands {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Playback") {
            Button(model.player.isPlaying ? "Pause" : "Play") { model.player.toggle() }
                .keyboardShortcut(.space, modifiers: .option)
            Button("Back 10 Seconds") { model.player.skip(-10) }.keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Forward 10 Seconds") { model.player.skip(10) }.keyboardShortcut(.rightArrow, modifiers: .command)
            Divider()
            Button("Start a Time Box…") { model.showTimeBox = true }.keyboardShortcut("t", modifiers: .command)
            Button("Floating Player") { openWindow(id: "floating") }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Command Palette…") { NotificationCenter.default.post(name: .boxtubeShowPalette, object: nil) }
        }
        CommandMenu("Boxtube") {
            Button(model.calmMode ? "Turn Off Calm Mode" : "Turn On Calm Mode") { model.calmMode.toggle() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button(model.mode == .music ? "Switch to Videos" : "Switch to Music") { model.mode = model.mode == .music ? .videos : .music }
                .keyboardShortcut("m", modifiers: [.command, .option])
            Button("Refresh Subscriptions") { Task { await model.refresh(force: true) } }.keyboardShortcut("r", modifiers: .command)
            Button("Keyboard Shortcuts") { NotificationCenter.default.post(name: .boxtubeShowShortcuts, object: nil) }
                .keyboardShortcut("/", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Floating player (always on top, snaps to a corner)

struct FloatingPlayerWindow: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.player.video != nil {
                PlayerSurface(engine: model.player)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "play.rectangle").font(.system(size: 26)).foregroundStyle(BX.muted)
                    Text("Nothing playing").font(.system(size: 13)).foregroundStyle(BX.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(BX.ground)
            }
            if hovering, model.player.video != nil {
                HStack(spacing: 14) {
                    Button { model.player.skip(-10) } label: { Image(systemName: "gobackward.10") }
                    Button { model.player.toggle() } label: { Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18)) }
                    Button { model.player.skip(10) } label: { Image(systemName: "goforward.10") }
                    Spacer()
                    Menu {
                        Button("Top left") { snap(.topLeading) }
                        Button("Top right") { snap(.topTrailing) }
                        Button("Bottom left") { snap(.bottomLeading) }
                        Button("Bottom right") { snap(.bottomTrailing) }
                    } label: { Image(systemName: "rectangle.inset.bottomright.filled") }
                    .menuStyle(.button).menuIndicator(.hidden).fixedSize()
                    .help("Snap to a corner")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 40)
                .boxGlass(Capsule())
                .padding(10)
                .transition(.opacity)
            }
        }
        .frame(minWidth: 320, idealWidth: 400, minHeight: 180, idealHeight: 225)
        .aspectRatio(16 / 9, contentMode: .fit)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .onAppear { snap(.bottomTrailing) }
    }

    private func snap(_ corner: Alignment) {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("floating") == true }), let screen = window.screen ?? NSScreen.main else { return }
        let v = screen.visibleFrame, f = window.frame, m: CGFloat = 24
        let x = corner == .topLeading || corner == .bottomLeading ? v.minX + m : v.maxX - f.width - m
        let y = corner == .topLeading || corner == .topTrailing ? v.maxY - f.height - m : v.minY + m
        window.setFrameOrigin(CGPoint(x: x, y: y))
        window.isMovableByWindowBackground = true
    }
}

// MARK: - Menu bar mini player

struct MenuBarPlayer: View {
    @Environment(AppModel.self) private var model
    /// Closes the menu bar panel.
    var close: () -> Void = {}
    /// Lets the panel follow the content's size.
    var resized: () -> Void = {}

    private func openWindow(id: String) {
        model.openWindowAction?(id)
        close()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let v = model.player.video {
                VideoThumbnail(v, radius: 10, showDuration: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(2)
                    Text([v.channelTitle, Chapter.current(in: v.chapters, at: model.player.state.time)?.title].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(BX.muted)
                }
                ProgressLine(value: model.player.state.progress, height: 3, track: .white.opacity(0.18)).clipShape(Capsule())
                HStack(spacing: 26) {
                    Button { model.player.skip(-10) } label: { Image(systemName: "gobackward.10") }
                    Button { model.player.toggle() } label: { Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20)) }
                    Button { model.advanceQueue() } label: { Image(systemName: "forward.end.fill") }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                if let next = model.segments.first?.video ?? model.player.queue.first {
                    Divider()
                    Text("Up next · \(Text(next.title).foregroundStyle(BX.text))").font(.system(size: 12)).foregroundStyle(BX.muted).lineLimit(1)
                }
            } else {
                Text("Nothing playing").font(.system(size: 13, weight: .semibold))
                Button("Start a time box") { model.showTimeBox = true; openWindow(id: "main") }
            }
            Divider()
            HStack {
                Button("Open Boxtube") { openWindow(id: "main"); NSApp.activate() }
                Spacer()
                Button("Floating player") { openWindow(id: "floating") }
            }
            .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(BX.coralText)
        }
        .padding(14)
        .frame(width: 300)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in resized() }
    }
}

// MARK: - Settings

struct MacSettings: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            TextField("Your name", text: $model.displayName)
            Toggle("Calm mode", isOn: $model.calmMode)
            Toggle("Tint the window from the video", isOn: $model.tintFromVideo)
            Picker("Preview videos on hover", selection: $model.previewMode) {
                ForEach(PreviewMode.allCases) { Text($0.title).tag($0) }
            }
            Picker("Watch later clears after", selection: $model.clearAfterWeeks) {
                ForEach([1, 2, 4, 8], id: \.self) { Text("\($0) week\($0 == 1 ? "" : "s")").tag($0) }
            }
            Toggle(isOn: $model.discoverChannels) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recommend from channels you don't follow")
                    if !model.recommendationStats.isEmpty {
                        Text(model.recommendationStats).font(.system(size: 11)).foregroundStyle(BX.muted)
                    }
                }
            }
            LabeledContent("YouTube API key", value: model.hasAPIKey ? "Added" : "Missing (apple/Config/Secrets.xcconfig)")
            Section {
                GoogleAccountSection()
            } header: { Text("YouTube account") } footer: {
                Text(model.syncEnabled
                         ? "Likes, subscriptions, playlist edits and new playlists go to YouTube; each change uses 50 of your 10,000 daily quota units. Deleting a playlist only removes it from Boxtube."
                         : "Boxtube copies your subscriptions, playlists and liked videos. Turn on sync to send changes you make here back to YouTube.")
            }
            HiddenVideosRow()
            Button("Clear watch history", role: .destructive) { Task { try? await model.store.clearHistory() } }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}

// MARK: - Music (Mac)

struct MacMusic: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var playlists: [PlaylistSummary] = []
    @State private var artists: [Q.SubscriptionRow] = []
    @State private var liked: [Video] = []
    @State private var feed: [Video] = []
    @State private var selected: String = "new"
    @State private var tracks: [Video] = []
    @State private var filter = LibraryFilter.playlists
    var onVideos: () -> Void = {}

    enum LibraryFilter: String, CaseIterable { case playlists = "Playlists", artists = "Artists", liked = "Liked" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                library.frame(width: 290)
                page
                nowPlaying.frame(width: 320)
            }
            .padding(.horizontal, 8).padding(.top, 8)
            playerBar
        }
        .observing(model.store, { db in try Q.playlists(db, music: true) }) { playlists = $0 }
        .observing(model.store, { db in try Q.subscriptions(db, music: true) }) { artists = $0 }
        .observing(model.store, { db in try Q.liked(db, music: true) }) { liked = $0 }
        .observing(model.store, { db in try Q.feed(db, music: true, limit: 80) }) { feed = $0 }
        .observing(model.store, id: selected, { [selected] db -> [Video] in
            if selected == "new" { return try Q.feed(db, music: true, limit: 50) }
            if selected == "liked" { return try Q.liked(db, music: true) }
            if selected.hasPrefix("UC") { return try Q.channelVideos(db, channelId: selected).filter { !$0.isShort } }
            return try Q.playlistVideos(db, id: selected)
        }) { tracks = $0 }
    }

    private var title: String {
        if selected == "new" { return "New from your artists" }
        if selected == "liked" { return "Liked music" }
        return playlists.first { $0.id == selected }?.playlist.title ?? artists.first { $0.id == selected }?.channel.title ?? "Music"
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                // The window's close / minimise / zoom buttons sit here (see MacRoot.lightCenters).
                Color.clear.frame(width: 52, height: 12)
                Spacer()
                HStack(spacing: 0) {
                    modeTab("Videos", on: false) { onVideos() }
                    modeTab("Music", on: true) {}
                }
                .padding(3)
                .frame(height: 30)
                .background(BX.ground, in: Capsule())
            }
            .padding(.horizontal, 4)
            .gesture(WindowDragGesture())
            HStack {
                Text("Your library").font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    Task { if let p = await model.createPlaylist(title: "New playlist", music: true) { selected = p.id } }
                } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(BX.text)
                        .frame(width: 30, height: 30).background(BX.surface3, in: Circle())
                }
                .buttonStyle(.plain)
                .help("New playlist")
                .accessibilityLabel("New playlist")
            }
            .padding(.horizontal, 4).padding(.top, 4)
            HStack(spacing: 6) {
                ForEach(LibraryFilter.allCases, id: \.self) { f in
                    Button { filter = f } label: {
                        Text(f.rawValue).font(.system(size: 12, weight: filter == f ? .bold : .semibold))
                            .foregroundStyle(filter == f ? BX.coralText : BX.text)
                            .padding(.horizontal, 11).frame(height: 28)
                            .background(filter == f ? BX.coral.opacity(0.18) : BX.surface3, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == f ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if filter != .artists {
                        libRow(id: "new", title: "New releases", meta: "From artists you follow", art: AnyView(ArtView(seed: "new", title: "NEW", showWord: false)))
                        libRow(id: "liked", title: "Liked music", meta: "\(liked.count) songs", art: AnyView(ZStack { BX.coral; Image(systemName: "heart.fill").foregroundStyle(BX.cream) }))
                    }
                    if filter == .playlists {
                        ForEach(playlists) { p in libRow(id: p.id, title: p.playlist.title, meta: "Playlist · \(p.count)", art: AnyView(ArtView(seed: p.id, title: p.playlist.title, showWord: false))) }
                    }
                    if filter != .liked {
                        ForEach(artists) { a in libRow(id: a.channel.id, title: a.channel.title, meta: "Artist", round: true, art: AnyView(ChannelAvatar(title: a.channel.title, url: a.channel.avatarURL, size: 44))) }
                    }
                    if filter == .liked {
                        ForEach(liked) { v in libRow(id: "v:" + v.id, title: v.title, meta: v.channelTitle, art: AnyView(VideoThumbnail(v, radius: 0, showDuration: false, aspect: 1))) }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 12).padding(.vertical, 14)
        .background(BX.surface, in: .rect(cornerRadius: 14))
    }

    private func modeTab(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: on ? .bold : .semibold))
                .foregroundStyle(on ? BX.coralInk : BX.muted)
                .padding(.horizontal, 12).frame(height: 24)
                .background(on ? BX.coral : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func libRow(id: String, title: String, meta: String, round: Bool = false, art: AnyView) -> some View {
        Button {
            if id.hasPrefix("v:"), let v = liked.first(where: { "v:" + $0.id == id }) { model.open(v, present: false); return }
            selected = id
        } label: {
            HStack(spacing: 11) {
                art.frame(width: 44, height: 44).clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(selected == id ? BX.coralText : BX.text).lineLimit(1)
                    Text(meta).font(.system(size: 12)).foregroundStyle(BX.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 6).frame(height: 56)
            .background(selected == id ? .white.opacity(0.06) : .clear, in: .rect(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var page: some View {
        let palette = ArtPalette.forSeed(selected)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(spacing: 0) {
                        UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8).fill(palette.circle.opacity(0.35)).frame(height: 7).padding(.horizontal, 20)
                        UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8).fill(palette.circle.opacity(0.65)).frame(height: 7).padding(.horizontal, 10)
                        ArtView(seed: selected, title: title).frame(width: 200, height: 200).clipShape(.rect(cornerRadius: 16))
                    }
                    .frame(width: 200)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Playlist").font(.system(size: 12.5, weight: .semibold))
                        Text(title).font(BX.display(56, .heavy)).kerning(-2).lineLimit(2).minimumScaleFactor(0.5)
                        Text("\(model.displayName) · \(tracks.count) songs · \(Format.minutes(Double(tracks.compactMap(\.durationSeconds).reduce(0, +))))")
                            .font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bg.opacity(0.55))

                HStack(spacing: 18) {
                    Button { play(tracks) } label: {
                        Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(BX.coralInk).frame(width: 56, height: 56).background(BX.coral, in: Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Play")
                    Button { play(tracks.shuffled()) } label: { Image(systemName: "shuffle").font(.system(size: 22)) }.buttonStyle(.plain).accessibilityLabel("Shuffle")
                    Button { model.showTimeBox = true } label: { Label("Fit to 25 min", systemImage: "timer").font(.system(size: 12.5, weight: .semibold)).padding(.horizontal, 12).frame(height: 32).background(BX.surface3, in: Capsule()) }
                        .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 28).padding(.vertical, 18)

                Grid(horizontalSpacing: 12, verticalSpacing: 0) {
                    GridRow {
                        Text("#").gridColumnAlignment(.trailing)
                        Text("Title").gridColumnAlignment(.leading)
                        Text("Added").gridColumnAlignment(.leading)
                        Text("Time").gridColumnAlignment(.trailing)
                    }
                    .font(.system(size: 12)).foregroundStyle(BX.dim)
                    .padding(.bottom, 8)
                    Divider().gridCellColumns(4)
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                        let on = model.player.video?.id == t.id
                        GridRow {
                            Group { if on { EqualizerBars(animating: model.player.isPlaying) } else { Text("\(i + 1)") } }
                                .foregroundStyle(on ? BX.coralText : BX.dim)
                            HStack(spacing: 11) {
                                VideoThumbnail(t, radius: 6, showDuration: false, aspect: 1).frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(on ? BX.coralText : BX.text).lineLimit(1)
                                    Text(t.channelTitle).font(.system(size: 12.5)).foregroundStyle(BX.muted)
                                }
                            }
                            Text(Format.ago(t.publishedAt)).font(.system(size: 12.5)).foregroundStyle(BX.muted)
                            Text(Format.clock(t.durationSeconds) ?? "–").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(BX.muted)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { play(Array(tracks[i...])) }
                        .contextMenu { Button("Play") { play(Array(tracks[i...])) }; Button("Like") { model.toggleLike(t.id) } }
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 28)
            }
        }
        .background(Color(hex: 0x121215), in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let v = model.player.video {
                Text(v.channelTitle).font(.system(size: 14, weight: .bold))
                PlayerSurface(engine: model.player).aspectRatio(16 / 9, contentMode: .fill).frame(width: 268, height: 268).clipShape(.rect(cornerRadius: 14))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.title).font(BX.display(19, .bold)).lineLimit(2)
                        Text(v.channelTitle).font(.system(size: 13)).foregroundStyle(BX.muted)
                    }
                    Spacer()
                    Button { model.toggleLike(v.id) } label: { Image(systemName: model.likedIds.contains(v.id) ? "heart.fill" : "heart").foregroundStyle(model.likedIds.contains(v.id) ? BX.coral : BX.text).font(.system(size: 20)) }
                        .buttonStyle(.plain)
                }
                Button { model.mode = .videos; model.watching = v } label: {
                    Label("Watch the music video", systemImage: "play.rectangle").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 38).background(BX.surface3, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                if let next = model.player.queue.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next in queue").font(.system(size: 13.5, weight: .bold))
                        HStack { VideoThumbnail(next, radius: 6, showDuration: false, aspect: 1).frame(width: 40); Text(next.title).font(.system(size: 13)).lineLimit(2) }
                    }
                    .padding(12).background(BX.surface2, in: .rect(cornerRadius: 12))
                }
            } else {
                Text("Nothing playing").foregroundStyle(BX.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(BX.surface, in: .rect(cornerRadius: 14))
    }

    private var playerBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 12) {
                if let v = model.player.video {
                    VideoThumbnail(v, radius: 8, showDuration: false, aspect: 1).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(v.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                        Text(v.channelTitle).font(.system(size: 12)).foregroundStyle(BX.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 6) {
                HStack(spacing: 22) {
                    Button { model.player.seek(to: 0) } label: { Image(systemName: "backward.end.fill") }
                    Button { model.player.toggle() } label: {
                        Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill").foregroundStyle(BX.ground).frame(width: 36, height: 36).background(BX.text, in: Circle())
                    }
                    Button { model.advanceQueue() } label: { Image(systemName: "forward.end.fill") }
                }
                .buttonStyle(.plain)
                HStack(spacing: 10) {
                    PlaybackText { Text(Format.clock($0.time)) }.font(.system(size: 11.5).monospacedDigit()).foregroundStyle(BX.muted)
                    ChapterScrubber(chapters: [], tint: BX.text, showsPreview: false)
                    Text(Format.clock(model.player.status.duration)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(BX.muted)
                }
            }
            .frame(width: 520)
            HStack {
                Spacer()
                if let v = model.player.video {
                    Button("Open in YouTube Music") { openURL(v.musicURL) }
                        .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 12).frame(height: 32).overlay(Capsule().strokeBorder(.white.opacity(0.2)))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .frame(height: 84)
    }

    private func play(_ list: [Video]) {
        guard let first = list.first else { return }
        model.player.queue = Array(list.dropFirst())
        model.open(first, present: false)
    }
}
