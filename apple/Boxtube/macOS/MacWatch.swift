import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

/// Mac watch page. Ideas 07 (notes), 08 (keyboard first) and 09 (colors from the video) live here.
struct MacWatchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var video: Video
    @State private var channel: Channel?
    @State private var upNext: [Video] = []
    @State private var notes: [Note] = []
    @State private var sidePanel = 0
    @State private var expanded = false
    @State private var showSkim = false
    @FocusState private var focused: Bool

    var body: some View {
        let v = model.player.video ?? video
        let chapters = v.chapters
        let p = model.tintFromVideo ? model.palette : .standard
        HStack(alignment: .top, spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack(alignment: .bottom) {
                        PlayerSurface(engine: model.player)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 18, style: .continuous))
                            .shadow(color: p.accent.opacity(model.tintFromVideo ? 0.3 : 0), radius: 50, y: 20)
                        NoteMarkers(notes: notes, duration: model.player.state.duration)
                            .padding(.horizontal, 28).padding(.bottom, 74)
                        PlayerControlBar(chapters: chapters, tint: p.accent, extra: AnyView(HStack(spacing: 8) {
                            Button { showSkim = true } label: { Image(systemName: "square.grid.2x2") }.help("Skim chapters (S)")
                            Button { openWindow(id: "floating") } label: { Image(systemName: "pip.enter") }.help("Floating player")
                        }.buttonStyle(.plain)))
                        .padding(14)
                    }

                    Text(v.title).font(BX.display(24, .bold)).kerning(-0.4).textSelection(.enabled)

                    HStack(spacing: 12) {
                        ChannelAvatar(title: v.channelTitle, url: channel?.avatarURL, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(v.channelTitle).font(.system(size: 15, weight: .semibold))
                            Text(Format.count(channel?.subscriberCount).map { "\($0) subscribers" } ?? Format.ago(v.publishedAt)).font(.system(size: 12.5)).foregroundStyle(p.muted)
                        }
                        let subscribed = channel?.isSubscribed ?? false
                        Button(subscribed ? "Subscribed" : "Subscribe") {
                            subscribed ? model.unsubscribe(v.channelId) : model.subscribe(channel ?? Channel(id: v.channelId, title: v.channelTitle))
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13.5, weight: .bold))
                        .padding(.horizontal, 16).frame(height: 36)
                        .foregroundStyle(subscribed ? BX.text : p.accentInk)
                        .background(subscribed ? p.surface : p.accent, in: Capsule())
                        Spacer()
                        actionButton(model.likedIds.contains(v.id) ? "Liked" : (Format.count(v.likeCount) ?? "Like"), icon: model.likedIds.contains(v.id) ? "hand.thumbsup.fill" : "hand.thumbsup", p: p) { model.toggleLike(v.id) }
                        actionButton(model.watchLaterIds.contains(v.id) ? "Saved" : "Save", icon: "clock", p: p) { model.toggleWatchLater(v.id) }
                        ShareLink(item: v.watchURL) { Label("Share", systemImage: "square.and.arrow.up").font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 14).frame(height: 36).background(p.surface, in: Capsule()) }
                            .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text([Format.views(v.viewCount), Format.ago(v.publishedAt)].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 13, weight: .semibold))
                        Text(v.summary.isEmpty ? "No description." : v.summary).font(.system(size: 13.5)).foregroundStyle(BX.text2)
                            .lineLimit(expanded ? nil : 3).textSelection(.enabled)
                        if !v.summary.isEmpty { Button(expanded ? "Show less" : "…more") { expanded.toggle() }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)) }
                        if !chapters.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                                ForEach(chapters) { c in
                                    let on = Chapter.current(in: chapters, at: model.player.state.time)?.index == c.index
                                    Button { model.player.seek(to: c.start) } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(Format.clock(c.start)).font(.system(size: 11.5, weight: .semibold).monospacedDigit()).foregroundStyle(on ? p.accent : BX.muted)
                                            Text(c.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(on ? p.accent.opacity(0.12) : BX.surface2, in: .rect(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? p.accent.opacity(0.45) : BX.line))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(p.surface, in: .rect(cornerRadius: 16))

                    if model.tintFromVideo && !p.swatches.isEmpty {
                        HStack(spacing: 10) {
                            Text("Palette from this video").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.muted)
                            ForEach(Array(p.swatches.enumerated()), id: \.offset) { _, c in Circle().fill(c).frame(width: 16, height: 16).overlay(Circle().strokeBorder(.white.opacity(0.3))) }
                            Spacer()
                            Toggle("Tint the window", isOn: Binding(get: { model.tintFromVideo }, set: { model.tintFromVideo = $0; if !$0 { model.palette = .standard } }))
                                .toggleStyle(.switch).controlSize(.small).font(.system(size: 12.5))
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 12) {
                Picker("Panel", selection: $sidePanel) {
                    Text("Up next").tag(0)
                    Text(notes.isEmpty ? "Notes" : "Notes · \(notes.count)").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if sidePanel == 0 {
                    ScrollView {
                        VStack(spacing: 14) {
                            if !model.segments.isEmpty {
                                HStack {
                                    Image(systemName: "timer").foregroundStyle(p.accent)
                                    Text("Time box · \(model.segments.count) more").font(.system(size: 13.5, weight: .semibold))
                                    Spacer()
                                }
                                .padding(12).background(p.surface, in: .rect(cornerRadius: 14))
                            }
                            ForEach(upNext) { n in
                                VideoRow(video: n, thumbWidth: 160) { model.open(n) }
                            }
                        }
                    }
                } else {
                    NotesPanel(video: v)
                        .background(p.surface, in: .rect(cornerRadius: 16))
                }
            }
            .frame(width: 372)
        }
        .padding(.horizontal, 24).padding(.top, 8)
        .sheet(isPresented: $showSkim) { SkimView(video: v).frame(width: 760, height: 560) }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(characters: .init(charactersIn: "jklcns,.?")) { press in handleKey(press.characters, chapters: chapters) }
        .observing(model.store, id: v.channelId, { [cid = v.channelId] db in try Channel.fetchOne(db, key: cid) }) { channel = $0 }
        .observing(model.store, id: v.id, { [vid = v.id] db in try Q.notes(db, videoId: vid) }) { notes = $0 }
        .observing(model.store, id: v.id, { [cid = v.channelId, vid = v.id] db in
            Array((try Q.channelVideos(db, channelId: cid).filter { $0.id != vid && !$0.isShort }.prefix(4)) + (try Q.feed(db, limit: 16).filter { $0.id != vid && $0.channelId != cid }))
        }) { upNext = $0; model.player.queue = $0 }
    }

    private func handleKey(_ key: String, chapters: [Chapter]) -> KeyPress.Result {
        switch key {
        case "j": model.player.skip(-10)
        case "k": model.player.toggle()
        case "l": model.player.skip(10)
        case ",": model.player.skip(-1 / 30)
        case ".": model.player.skip(1 / 30)
        case "c":
            let t = model.player.state.time
            if let next = chapters.first(where: { $0.start > t + 1 }) { model.player.seek(to: next.start) }
        case "n": sidePanel = 1
        case "s": showSkim = true
        case "?": NotificationCenter.default.post(name: .boxtubeShowShortcuts, object: nil)
        default: return .ignored
        }
        return .handled
    }

    private func actionButton(_ title: String, icon: String, p: VideoPalette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 14).frame(height: 36).background(p.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Diamond markers above the scrubber where notes are pinned.
private struct NoteMarkers: View {
    var notes: [Note]
    var duration: Double
    var body: some View {
        GeometryReader { geo in
            ForEach(notes) { n in
                RoundedRectangle(cornerRadius: 2).fill(BX.amber).frame(width: 9, height: 9).rotationEffect(.degrees(45))
                    .position(x: geo.size.width * CGFloat(n.time / max(duration, 1)), y: geo.size.height - 5)
                    .help(n.text)
            }
        }
        .frame(height: 12)
        .allowsHitTesting(false)
    }
}

/// Idea 08: ⌘K command palette.
struct MacCommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Binding var isPresented: Bool
    @Binding var section: MacSection?
    @State private var text = ""
    @State private var selection = 0
    @State private var videos: [Video] = []
    @FocusState private var focused: Bool

    struct Item: Identifiable { var id: String; var title: String; var keys: String; var icon: String; var tint: Color; var run: () -> Void }

    var body: some View {
        let items = filtered
        ZStack(alignment: .top) {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { isPresented = false }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right").foregroundStyle(BX.coralText).font(.system(size: 15, weight: .bold))
                    TextField("Type a command or search", text: $text)
                        .textFieldStyle(.plain).font(.system(size: 17, weight: .medium))
                        .focused($focused)
                        .onSubmit { run(items) }
                    Text("esc").font(.system(size: 11, weight: .semibold)).foregroundStyle(BX.muted).padding(.horizontal, 7).padding(.vertical, 3).background(Color(hex: 0x2A2A30), in: .rect(cornerRadius: 6))
                }
                .padding(.horizontal, 18).frame(height: 56)
                Divider().overlay(BX.line)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            Button { selection = i; run(items) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.icon).font(.system(size: 12, weight: .bold)).foregroundStyle(item.tint)
                                        .frame(width: 26, height: 26).background(item.tint.opacity(0.18), in: .rect(cornerRadius: 7))
                                    Text(item.title).font(.system(size: 14)).lineLimit(1)
                                    Spacer()
                                    Text(item.keys).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(BX.muted)
                                }
                                .padding(.horizontal, 10).frame(height: 42)
                                .background(i == selection ? .white.opacity(0.08) : .clear, in: .rect(cornerRadius: 10))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 380)
                Divider().overlay(BX.line)
                HStack(spacing: 18) { Text("↑↓ move"); Text("↩ run"); Text("type to search YouTube") }
                    .font(.system(size: 12)).foregroundStyle(BX.dim).padding(.horizontal, 18).frame(height: 36).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 620)
            .background(Color(hex: 0x18181C, opacity: 0.96), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
            .padding(.top, 90)
        }
        .onAppear { focused = true }
        .onKeyPress(.escape) { isPresented = false; return .handled }
        .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, items.count - 1)); return .handled }
        .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
        .onChange(of: text) { _, _ in selection = 0 }
        .observing(model.store, { db in try Q.feed(db, limit: 200) }) { videos = $0 }
    }

    private var commands: [Item] {
        [
            Item(id: "tb", title: "Start a 25 minute time box", keys: "⌘T", icon: "timer", tint: BX.coralText) { model.showTimeBox = true },
            Item(id: "calm", title: model.calmMode ? "Turn off Calm mode" : "Turn on Calm mode", keys: "⌘⇧C", icon: "leaf.fill", tint: BX.sageText) { model.calmMode.toggle(); section = .home },
            Item(id: "music", title: model.mode == .music ? "Switch to Videos" : "Switch to Music", keys: "⌘M", icon: "music.note", tint: BX.amber) { model.mode = model.mode == .music ? .videos : .music; section = model.mode == .music ? .music : .home },
            Item(id: "later", title: "Open Watch later", keys: "", icon: "clock", tint: BX.teal) { section = .watchLater },
            Item(id: "float", title: "Open floating player", keys: "⌘⇧P", icon: "pip.enter", tint: Color(hex: 0x8FB0F2)) { openWindow(id: "floating") },
            Item(id: "keys", title: "Show keyboard shortcuts", keys: "?", icon: "keyboard", tint: BX.muted) { NotificationCenter.default.post(name: .boxtubeShowShortcuts, object: nil) },
            Item(id: "refresh", title: "Refresh subscriptions", keys: "⌘R", icon: "arrow.clockwise", tint: BX.muted) { Task { await model.refresh(force: true) } },
        ]
    }

    private var filtered: [Item] {
        let q = text.trimmingCharacters(in: .whitespaces)
        var list = commands.filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) || (q.lowercased().hasPrefix("time") && $0.id == "tb") }
        if !q.isEmpty {
            list += videos.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.channelTitle.localizedCaseInsensitiveContains(q) }.prefix(6).map { v in
                Item(id: v.id, title: v.title, keys: v.channelTitle, icon: "play.fill", tint: BX.text) { model.open(v) }
            }
            if model.hasAPIKey {
                list.append(Item(id: "search", title: "Search YouTube for “\(q)”", keys: "↩", icon: "magnifyingglass", tint: BX.coralText) {
                    model.rememberSearch(q); model.watching = nil; model.paths[.home, default: []].append(.search(q))
                })
            }
        }
        return list
    }

    private func run(_ items: [Item]) {
        guard items.indices.contains(selection) else { return }
        isPresented = false
        items[selection].run()
    }
}

struct ShortcutHUD: View {
    private let keys: [(String, String)] = [("J", "−10s"), ("K", "Play/pause"), ("L", "+10s"), (", .", "Frame"), ("C", "Next chapter"), ("S", "Skim"), ("N", "Note"), ("⌘K", "Commands")]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.0) { k in
                HStack(spacing: 7) {
                    Text(k.0).font(.system(size: 12, weight: .bold)).foregroundStyle(BX.ground)
                        .padding(.horizontal, 7).frame(minWidth: 24, minHeight: 24).background(BX.text, in: .rect(cornerRadius: 6))
                        .shadow(color: BX.dim, radius: 0, y: 2)
                    Text(k.1).font(.system(size: 12.5)).foregroundStyle(BX.text2)
                }
                .padding(.leading, 6).padding(.trailing, 10).frame(height: 36)
                .background(.white.opacity(0.05), in: .rect(cornerRadius: 10))
            }
        }
        .padding(8)
        .boxGlass(.rect(cornerRadius: 16))
    }
}
