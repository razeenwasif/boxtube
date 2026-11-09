import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

extension Notification.Name {
    static let boxtubeFocusNote = Notification.Name("boxtube.focusNote")
}

/// Mac watch page, laid out like the macOS · Watch artboard. Notes (07) swap the right column for the
/// notes panel; colours from the video (09) tint the panels when that setting is on.
struct MacWatchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var video: Video
    @State private var channel: Channel?
    @State private var related: [Video] = []
    @State private var notes: [Note] = []
    @State private var playlists: [PlaylistSummary] = []
    @State private var expanded = false
    @State private var showSkim = false
    @State private var disliked: Set<String> = []
    @State private var scrolledY: CGFloat = 0
    @FocusState private var focused: Bool

    private var tinted: Bool { model.tintFromVideo && model.palette != .standard }
    private var p: VideoPalette { tinted ? model.palette : .standard }
    private var panel: Color { tinted ? model.palette.surface : Color(hex: 0x141417) }
    private var chip: Color { tinted ? model.palette.surface : Color(hex: 0x1C1C20) }
    private var muted: Color { tinted ? model.palette.muted : BX.muted }

    var body: some View {
        let v = model.player.video ?? video
        Group {
            if model.showNotes { notesLayout(v) } else { watchLayout(v) }
        }
        .sheet(isPresented: $showSkim) { SkimView(video: v).frame(width: 760, height: 560) }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(characters: .init(charactersIn: "jklcnsf,.?")) { press in handleKey(press.characters, chapters: v.chapters) }
        // YouTube's keys: Space plays or pauses, the arrows move 5 seconds. Text fields keep their own keys.
        .onKeyPress(.space) { model.player.toggle(); return .handled }
        .onKeyPress(.leftArrow) { model.player.skip(-5); return .handled }
        .onKeyPress(.rightArrow) { model.player.skip(5); return .handled }
        .observing(model.store, id: v.channelId, { [cid = v.channelId] db in try Channel.fetchOne(db, key: cid) }) { channel = $0 }
        .observing(model.store, id: v.id, { [vid = v.id] db in try Q.notes(db, videoId: vid) }) { notes = $0 }
        .observing(model.store, { db in try Q.playlists(db) }) { playlists = $0 }
        .observing(model.store, id: v.id, { [cid = v.channelId, vid = v.id] db in
            Array((try Q.channelVideos(db, channelId: cid).filter { $0.id != vid && !$0.isShort }.prefix(4)) + (try Q.feed(db, limit: 16).filter { $0.id != vid && $0.channelId != cid }))
        }) { related = $0; if model.playingFrom == nil { model.player.queue = $0 } }
    }

    /// What plays after this one: the rest of the time box or list it came from, otherwise related videos.
    private func upNext(_ v: Video) -> [Video] {
        if !model.segments.isEmpty { return model.segments.map(\.video) }
        if let from = model.playingFrom, let i = from.position(of: v.id) { return Array(from.videos.dropFirst(i)) }
        return related
    }

    // MARK: Layouts

    private func watchLayout(_ v: Video) -> some View {
        // One page that scrolls as a whole and starts right at the rail, so the video's glow
        // can spread and fade out instead of being cut at a column edge.
        ScrollView {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    player(v, notesMode: false)
                    Text(v.title).font(BX.display(24, .bold)).kerning(-0.48).lineSpacing(2).textSelection(.enabled)
                    channelRow(v)
                    descriptionCard(v)
                }
                rightColumn(v).frame(width: 372)
            }
            .padding(.leading, 20).padding(.trailing, 24).padding(.top, 4).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in scrolledY = y }
        // Once scrolled, the page fades out under the top bar instead of stopping at a hard line.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: max(0.5, min(scrolledY, 36)))
                Color.black
            }
        }
    }

    private func notesLayout(_ v: Video) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                player(v, notesMode: true)
                Text(v.title).font(BX.display(24, .bold)).kerning(-0.48).textSelection(.enabled)
                HStack(spacing: 0) {
                    Text([v.channelTitle, Format.views(v.viewCount)].compactMap { $0 }.joined(separator: " · "))
                    if let from = model.playingFrom {
                        Text(" · In playlist ")
                        Button(from.title) { openPlayingFrom(from) }.buttonStyle(.plain).foregroundStyle(BX.coralText)
                    }
                }
                .font(.system(size: 13.5)).foregroundStyle(muted)
                Spacer(minLength: 0)
            }
            MacNotesPanel(video: v, notes: notes)
                .frame(width: 420)
                .frame(maxHeight: .infinity)
        }
        .padding(20)
    }

    // MARK: Player

    private func player(_ v: Video, notesMode: Bool) -> some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay { PlayerSurface(engine: model.player) }
            .overlay(alignment: .topTrailing) { if !notesMode { addToPlaylist(v).padding(14) } }
            .overlay(alignment: .bottom) {
                MacPlayerBar(chapters: v.chapters, accent: p.accent, notes: notesMode ? notes : nil, showSkim: $showSkim)
                    .padding(14)
            }
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .background { if tinted { ambientGlow } }
    }

    /// Light from the video spilling onto the page: wide, soft, and cast downward, so it fades out
    /// before any edge (it starts below the player's top, so nothing is cut under the top bar).
    private var ambientGlow: some View {
        RoundedRectangle(cornerRadius: 60, style: .continuous)
            .fill(p.accent)
            .padding(.top, 170)
            .padding(.horizontal, -24)
            .blur(radius: 60)
            .opacity(0.45)
            .offset(y: 50)
            .allowsHitTesting(false)
    }

    private func addToPlaylist(_ v: Video) -> some View {
        Menu {
            Button(model.watchLaterIds.contains(v.id) ? "Remove from Watch later" : "Watch later") { model.toggleWatchLater(v.id) }
            if !playlists.isEmpty {
                Divider()
                ForEach(playlists) { pl in Button(pl.playlist.title) { model.add(v.id, to: pl.playlist) } }
            }
        } label: {
            Image(systemName: "text.badge.plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(hex: 0x0C0C10, opacity: 0.5), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize()
        .help("Add to playlist")
        .accessibilityLabel("Add to playlist")
    }

    // MARK: Channel row

    private func channelRow(_ v: Video) -> some View {
        let subscribed = channel?.isSubscribed ?? false
        let liked = model.likedIds.contains(v.id)
        return HStack(spacing: 12) {
            ChannelAvatar(title: v.channelTitle, url: channel?.avatarURL, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(v.channelTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(Format.count(channel?.subscriberCount).map { "\($0) subscribers" } ?? Format.ago(v.publishedAt))
                    .font(.system(size: 12.5)).foregroundStyle(muted)
            }
            Group {
                if subscribed {
                    Menu {
                        Button("Unsubscribe", role: .destructive) { model.unsubscribe(v.channelId) }
                    } label: {
                        HStack(spacing: 7) {
                            IconView(.bell, size: 16, lineWidth: 1.8)
                            Text("Subscribed")
                            IconView(.chevronDown, size: 13, lineWidth: 2)
                        }
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(BX.text)
                        .padding(.horizontal, 16).frame(height: 36)
                        .background(tinted ? p.surface : Color(hex: 0x232327), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                } else {
                    Button { model.subscribe(channel ?? Channel(id: v.channelId, title: v.channelTitle)) } label: {
                        Text("Subscribe").font(.system(size: 13.5, weight: .bold)).foregroundStyle(p.accentInk)
                            .padding(.horizontal, 16).frame(height: 36).background(p.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 8)
            Spacer(minLength: 12)
            HStack(spacing: 0) {
                Button {
                    model.toggleLike(v.id); disliked.remove(v.id)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsup").font(.system(size: 14, weight: .medium))
                        Text(Format.count(v.likeCount) ?? "Like").lineLimit(1)
                    }
                    .fixedSize()
                    .foregroundStyle(liked ? BX.coralText : BX.text2)
                    .padding(.horizontal, 14).frame(maxHeight: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(liked ? "Liked" : "Like")
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1).padding(.vertical, 9)
                Button {
                    if disliked.contains(v.id) { disliked.remove(v.id) } else { disliked.insert(v.id); if liked { model.toggleLike(v.id) } }
                } label: {
                    Image(systemName: disliked.contains(v.id) ? "hand.thumbsdown.fill" : "hand.thumbsdown").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BX.text2).padding(.horizontal, 13).frame(maxHeight: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dislike")
            }
            .font(.system(size: 13.5, weight: .semibold))
            .frame(height: 36)
            .background(chip, in: Capsule())
            ShareLink(item: v.watchURL) {
                chipLabel(icon: AnyView(IconView(.share, size: 16, lineWidth: 1.8)), title: "Share")
            }
            .buttonStyle(.plain)
            Button { model.toggleWatchLater(v.id) } label: {
                chipLabel(icon: AnyView(IconView(.clock, size: 16, lineWidth: 1.8)), title: model.watchLaterIds.contains(v.id) ? "Saved" : "Save")
            }
            .buttonStyle(.plain)
            .help("Save to Watch later")
            Menu {
                Button("Skim chapters") { showSkim = true }
                Button("Open floating player") { openWindow(id: "floating") }
                Divider()
                Button("Copy link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(v.watchURL.absoluteString, forType: .string) }
                Button("Open on YouTube") { NSWorkspace.shared.open(v.watchURL) }
            } label: {
                MoreDots().foregroundStyle(BX.text2).frame(width: 36, height: 36).background(chip, in: Circle()).contentShape(Circle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("More actions")
        }
    }

    private func chipLabel(icon: AnyView, title: String) -> some View {
        HStack(spacing: 7) { icon; Text(title) }
            .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(BX.text2)
            .padding(.horizontal, 14).frame(height: 36)
            .background(chip, in: Capsule())
            .contentShape(Capsule())
    }

    // MARK: Description

    private func descriptionCard(_ v: Video) -> some View {
        let chapters = v.chapters
        let current = Chapter.current(in: chapters, at: model.player.state.time)?.index
        let tags = Self.hashtags(in: v.summary)
        let meta = [Format.views(v.viewCount), Format.ago(v.publishedAt)].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(meta)\(tags.isEmpty ? "" : " ")\(Text(tags).foregroundStyle(BX.coralText).fontWeight(.medium))")
                .font(.system(size: 13, weight: .semibold))
            if !v.summary.isEmpty {
                Text(v.summary).font(.system(size: 13.5)).lineSpacing(7.4 - 13.5 * 0.2).foregroundStyle(BX.text2)
                    .lineLimit(expanded ? nil : 2).textSelection(.enabled)
                    .frame(maxWidth: 760, alignment: .leading)
                Button(expanded ? "Show less" : "…more") { withAnimation(.snappy) { expanded.toggle() } }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(BX.text)
            }
            if !chapters.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(chapters) { c in
                        let on = c.index == current
                        Button { model.player.seek(to: c.start) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(Format.clock(c.start)).font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(on ? BX.coralText : BX.muted)
                                Text(c.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(BX.text).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(8)
                            .background(on ? BX.coral.opacity(0.12) : chip, in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? BX.coral.opacity(0.45) : .white.opacity(0.04)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 14).padding(.horizontal, 16).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panel, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.06)))
    }

    static func hashtags(in text: String) -> String {
        let matches = text.matches(of: /#[\p{L}\p{N}_]+/).map { String($0.output) }
        var seen = Set<String>()
        return matches.filter { seen.insert($0.lowercased()).inserted }.prefix(3).joined(separator: " ")
    }

    // MARK: Right column

    private func rightColumn(_ v: Video) -> some View {
        let next = upNext(v)
        return VStack(alignment: .leading, spacing: 14) {
            if let card = playingFromCard(v) { card }
            HStack {
                Text("Up next").font(.system(size: 16, weight: .bold))
                Spacer()
                HStack(spacing: 8) {
                    Text("Autoplay").font(.system(size: 12.5)).foregroundStyle(muted)
                    BXSwitch(isOn: Binding(get: { model.autoplay }, set: { model.autoplay = $0 }), tint: p.accent, width: 34, height: 20)
                        .accessibilityLabel("Autoplay")
                }
            }
            .padding(.top, 4).padding(.horizontal, 2)
            ForEach(next) { n in
                Button { model.open(n) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VideoThumbnail(n, radius: 11).frame(width: 168)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(n.title).font(.system(size: 13.5, weight: .semibold)).lineSpacing(1.5).lineLimit(2).multilineTextAlignment(.leading)
                            Text(n.channelTitle).font(.system(size: 12)).foregroundStyle(muted).lineLimit(1)
                            Text([Format.views(n.viewCount), Format.ago(n.publishedAt)].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 12)).foregroundStyle(muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func playingFromCard(_ v: Video) -> AnyView? {
        let title: String, detail: String, cover: Video?
        if !model.segments.isEmpty {
            title = "Time box"; detail = "\(model.segments.count) more"; cover = model.segments.first?.video
        } else if let from = model.playingFrom, let i = from.position(of: v.id) {
            title = from.title; detail = "\(i) of \(from.videos.count)"; cover = from.videos.first
        } else { return nil }
        return AnyView(HStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8).fill(BX.coral.opacity(0.35)).frame(height: 40).padding(.horizontal, 6)
                    .frame(maxHeight: .infinity, alignment: .top)
                Group {
                    if let cover { VideoThumbnail(cover, radius: 0, showDuration: false, aspect: 44 / 38) } else { Color(hex: 0x1B2A4A) }
                }
                .frame(height: 38).clipShape(.rect(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.12)))
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("PLAYING FROM").font(.system(size: 11, weight: .bold)).kerning(0.66).foregroundStyle(BX.dim)
                Text("\(title) \(Text("· \(detail)").foregroundStyle(muted).fontWeight(.medium))")
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let from = model.playingFrom, model.segments.isEmpty {
                Button { openPlayingFrom(from) } label: {
                    IconView(.chevronRight, size: 16, lineWidth: 2).foregroundStyle(BX.muted).frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show playlist")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(panel, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.06))))
    }

    private func openPlayingFrom(_ from: AppModel.PlayingFrom) {
        guard let id = from.playlistId else { return }
        model.showNotes = false
        model.watching = nil
        model.paths[.home, default: []].append(.playlist(id))
    }

    // MARK: Keys (idea 08)

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
        case "n":
            withAnimation(.snappy) { model.showNotes = true }
            DispatchQueue.main.async { NotificationCenter.default.post(name: .boxtubeFocusNote, object: nil) }
        case "s": showSkim = true
        case "f": NSApp.keyWindow?.toggleFullScreen(nil)
        case "?": NotificationCenter.default.post(name: .boxtubeShowShortcuts, object: nil)
        default: return .ignored
        }
        return .handled
    }
}

/// Small pill switch used by Autoplay and the palette pill.
struct BXSwitch: View {
    @Binding var isOn: Bool
    var tint: Color = BX.coral
    var width: CGFloat = 34
    var height: CGFloat = 20
    var knob: Color = .white
    var body: some View {
        Button { withAnimation(.snappy(duration: 0.2)) { isOn.toggle() } } label: {
            Capsule().fill(isOn ? tint : .white.opacity(0.18))
                .frame(width: width, height: height)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(knob).frame(width: height - 4, height: height - 4).padding(2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Player bar (glass bar inside the video)

struct MacPlayerBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var chapters: [Chapter]
    var accent: Color
    /// Non-nil on the notes layout: shows note markers and the "Press N" hint instead of the full controls.
    var notes: [Note]?
    @Binding var showSkim: Bool
    @State private var hoverX: CGFloat?
    @State private var dragging = false

    private let rates: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    var body: some View {
        let s = model.player.state
        VStack(spacing: notes == nil ? 8 : 10) {
            scrubber(s)
            if let notes { notesControls(s, count: notes.count) } else { controls(s) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(Color(hex: 0x0C0C10, opacity: notes == nil ? 0.58 : 0.6), in: .rect(cornerRadius: 16, style: .continuous))
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }

    // MARK: Scrubber

    private func scrubber(_ s: PlayerEngine.State) -> some View {
        let duration = max(s.duration, 1)
        let parts = chapters.isEmpty ? [Chapter(index: 0, title: "", start: 0, end: duration)] : chapters
        let gap: CGFloat = notes == nil && !chapters.isEmpty ? 3 : 0
        return GeometryReader { geo in
            let w = geo.size.width
            let usable = max(1, w - gap * CGFloat(parts.count - 1))
            let knobX = w * CGFloat(s.time / duration)
            ZStack(alignment: .leading) {
                HStack(spacing: gap) {
                    ForEach(parts) { c in
                        let fill = c.length > 0 ? min(1, max(0, (s.time - c.start) / c.length)) : 0
                        let live = notes == nil && fill > 0 && fill < 1
                        Capsule().fill(.white.opacity(0.25))
                            .overlay(alignment: .leading) {
                                GeometryReader { g in Rectangle().fill(BX.coral).frame(width: g.size.width * fill) }
                            }
                            .clipShape(.rect(cornerRadius: live ? 3 : 2))
                            .frame(width: usable * CGFloat(c.length / duration), height: live ? 6 : 4)
                    }
                }
                .frame(maxHeight: .infinity, alignment: notes == nil ? .center : .bottom)
                if let notes {
                    ForEach(notes) { n in
                        RoundedRectangle(cornerRadius: 3).fill(BX.amber).frame(width: 10, height: 10)
                            .shadow(color: Color(hex: 0x0C0C10, opacity: 0.8), radius: 0)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0x0C0C10, opacity: 0.8), lineWidth: 2).padding(-2))
                            .rotationEffect(.degrees(45))
                            .position(x: w * CGFloat(n.time / duration), y: 5)
                            .help(n.text)
                            .onTapGesture { model.player.seek(to: n.time) }
                    }
                } else {
                    Circle().fill(.white).frame(width: 14, height: 14)
                        .background(Circle().fill(BX.coral.opacity(0.35)).padding(-4))
                        .position(x: knobX, y: geo.size.height / 2)
                        .opacity(s.duration > 0 ? 1 : 0)
                }
                if notes == nil, let x = hoverX {
                    preview(at: x, width: w, duration: duration)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let p) = phase { hoverX = min(max(0, p.x), w) } else if !dragging { hoverX = nil }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in dragging = true; hoverX = min(max(0, g.location.x), w) }
                .onEnded { g in
                    dragging = false
                    model.player.seek(to: Double(min(max(0, g.location.x), w) / w) * duration)
                })
        }
        .frame(height: notes == nil ? 16 : 20)
        .accessibilityElement()
        .accessibilityLabel("Seek")
        .accessibilityValue("\(Format.clock(s.time)) of \(Format.clock(s.duration))")
        .accessibilityAdjustableAction { dir in model.player.skip(dir == .increment ? 10 : -10) }
    }

    /// Hover preview: the video's thumbnail with the chapter and time under the pointer.
    /// (YouTube doesn't expose per-time preview frames to embeds, so this uses the video thumbnail.)
    private func preview(at x: CGFloat, width: CGFloat, duration: Double) -> some View {
        let t = Double(x / max(width, 1)) * duration
        let name = Chapter.current(in: chapters, at: t)?.title
        return VStack(spacing: 6) {
            Group {
                if let v = model.player.video { VideoThumbnail(v, radius: 0, showDuration: false) } else { Color(hex: 0x1B2A4A) }
            }
            .frame(width: 148, height: 148 * 9 / 16)
            .clipShape(.rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white, lineWidth: 2))
            Text([name, Format.clock(t)].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(hex: 0x0C0C10, opacity: 0.8), in: .rect(cornerRadius: 6))
                .fixedSize()
        }
        .position(x: min(max(x, 80), width - 80), y: -22 - 54)
        .allowsHitTesting(false)
    }

    // MARK: Controls

    private func controls(_ s: PlayerEngine.State) -> some View {
        let chapter = Chapter.current(in: chapters, at: s.time)
        return HStack(spacing: 4) {
            icon(s.isPlaying ? "pause.fill" : "play.fill", s.isPlaying ? "Pause" : "Play", size: 18) { model.player.toggle() }
            icon("forward.end.fill", "Next video", size: 15) { model.advanceQueue() }
            icon(model.player.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", model.player.muted ? "Unmute" : "Mute", size: 15) {
                model.player.setMuted(!model.player.muted)
            }
            Text("\(Format.clock(s.time)) \(Text("/ \(Format.clock(s.duration))").foregroundStyle(.white.opacity(0.6)))")
                .font(.system(size: 12.5).monospacedDigit())
                .padding(.leading, 6)
            if let chapter {
                Text("· \(chapter.title)").font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    .padding(.leading, 10)
            }
            Spacer(minLength: 8)
            icon(model.player.captionsOn ? "captions.bubble.fill" : "captions.bubble", "Captions", size: 16) {
                model.player.setCaptions(!model.player.captionsOn)
            }
            Menu {
                ForEach(rates, id: \.self) { r in
                    Button { model.player.setRate(r) } label: {
                        if r == s.rate { Label(Self.rate(r), systemImage: "checkmark") } else { Text(Self.rate(r)) }
                    }
                }
            } label: {
                Text(Self.rate(s.rate)).font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 8).frame(height: 28)
                    .background(.white.opacity(0.12), in: .rect(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Playback speed")
            icon("pip.enter", "Picture in picture", size: 16) { openWindow(id: "floating") }
            icon("arrow.up.left.and.arrow.down.right", "Full screen", size: 15) { NSApp.keyWindow?.toggleFullScreen(nil) }
        }
    }

    private func notesControls(_ s: PlayerEngine.State, count: Int) -> some View {
        HStack(spacing: 12) {
            icon(s.isPlaying ? "pause.fill" : "play.fill", s.isPlaying ? "Pause" : "Play", size: 16, frame: 32) { model.player.toggle() }
            Text("\(Format.clock(s.time)) \(Text("/ \(Format.clock(s.duration))").foregroundStyle(.white.opacity(0.6)))")
                .monospacedDigit()
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(BX.amber).frame(width: 8, height: 8).rotationEffect(.degrees(45))
                Text(count == 1 ? "1 note" : "\(count) notes")
            }
            .foregroundStyle(BX.amber).fontWeight(.semibold)
            Spacer()
            HStack(spacing: 4) {
                Text("Press")
                Text("N").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(.white.opacity(0.14), in: .rect(cornerRadius: 5))
                Text("to note this moment")
            }
            .foregroundStyle(.white.opacity(0.7))
        }
        .font(.system(size: 12.5))
    }

    private func icon(_ name: String, _ label: String, size: CGFloat, frame: CGFloat = 36, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: size, weight: .semibold))
                .frame(width: frame, height: frame).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    static func rate(_ r: Double) -> String {
        (r == r.rounded() ? String(Int(r)) : String(format: "%g", r)) + "×"
    }
}

// MARK: - Notes panel (macOS · Notes artboard)

struct MacNotesPanel: View {
    @Environment(AppModel.self) private var model
    var video: Video
    var notes: [Note]
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes").font(.system(size: 16, weight: .bold))
                    Text("Click a time to jump there").font(.system(size: 12)).foregroundStyle(BX.muted)
                }
                Spacer()
                Button(action: export) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 12, weight: .semibold))
                        Text("Export .md")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(BX.surface3, in: .rect(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(notes.isEmpty)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if notes.isEmpty {
                        Text("Press N to pin a thought to this moment. Notes stay with the video and export as Markdown.")
                            .font(.system(size: 13)).foregroundStyle(BX.muted).padding(.top, 4)
                    }
                    ForEach(notes) { n in NoteRow(note: n) }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Text(Format.clock(model.player.state.time)).font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(BX.coralText).padding(.horizontal, 7).frame(height: 22)
                        .background(BX.coral.opacity(0.16), in: .rect(cornerRadius: 6))
                    TextField("Write a note for this moment", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .lineLimit(2...6)
                        .focused($focused)
                        .onKeyPress(.return, phases: .down) { press in
                            guard press.modifiers.contains(.command) else { return .ignored }
                            save(); return .handled
                        }
                        .onKeyPress(.escape) { focused = false; return .handled }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(BX.ground, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BX.coral.opacity(focused ? 0.55 : 0.25), lineWidth: 1.5))
                HStack {
                    Text("Notes stay on this Mac")
                    Spacer()
                    Text("Save ⌘↩")
                }
                .font(.system(size: 11.5)).foregroundStyle(BX.dim)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
        }
        .background(Color(hex: 0x131316), in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.07)))
        .onReceive(NotificationCenter.default.publisher(for: .boxtubeFocusNote)) { _ in focused = true }
    }

    private func save() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let time = model.player.state.time
        draft = ""
        Task { _ = try? await model.store.addNote(videoId: video.id, time: time, text: text) }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(video.title.replacingOccurrences(of: "/", with: "-")) notes.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var out = "# \(video.title)\n\n\(video.channelTitle) · \(video.watchURL.absoluteString)\n\n"
        for n in notes {
            out += "- [\(Format.clock(n.time))](\(video.watchURL.absoluteString)&t=\(Int(n.time))s) \(n.text)\n"
        }
        try? out.write(to: url, atomically: true, encoding: .utf8)
    }

    /// One note: amber time chip, text, and any ``` fenced code shown as a code block.
    private struct NoteRow: View {
        @Environment(AppModel.self) private var model
        var note: Note
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Button { model.player.seek(to: note.time) } label: {
                    Text(Format.clock(note.time)).font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(BX.amber).padding(.horizontal, 8).frame(height: 24)
                        .background(BX.amber.opacity(0.14), in: .rect(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Jump to \(Format.clock(note.time))")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(Self.parts(note.text).enumerated()), id: \.offset) { _, part in
                        if part.code {
                            Text(part.text).font(.system(size: 12, weight: .medium, design: .monospaced)).lineSpacing(6.6 - 12 * 0.2)
                                .foregroundStyle(Color(hex: 0xC7C7CC))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(BX.ground, in: .rect(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
                        } else {
                            Text(part.text).font(.system(size: 13.5)).lineSpacing(6.75 - 13.5 * 0.2).foregroundStyle(Color(hex: 0xE4E4E7))
                        }
                    }
                }
                .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .contextMenu {
                Button(role: .destructive) { if let id = note.id { Task { try? await model.store.deleteNote(id) } } } label: { Label("Delete note", systemImage: "trash") }
            }
        }

        static func parts(_ text: String) -> [(text: String, code: Bool)] {
            text.components(separatedBy: "```").enumerated().compactMap { i, chunk in
                let t = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : (t, i % 2 == 1)
            }
        }
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
            Item(id: "music", title: model.mode == .music ? "Switch to Videos" : "Switch to Music", keys: "⌥⌘M", icon: "music.note", tint: BX.amber) { model.mode = model.mode == .music ? .videos : .music; section = model.mode == .music ? .music : .home },
            Item(id: "later", title: "Open Watch later", keys: "", icon: "clock", tint: BX.teal) { section = .watchLater },
            Item(id: "float", title: "Open floating player", keys: "⌘⇧P", icon: "pip.enter", tint: Color(hex: 0x8FB0F2)) { openWindow(id: "floating") },
            Item(id: "keys", title: "Show keyboard shortcuts", keys: "?", icon: "keyboard", tint: BX.muted) { NotificationCenter.default.post(name: .boxtubeShowShortcuts, object: nil) },
            Item(id: "refresh", title: "Refresh subscriptions", keys: "⌘R", icon: "arrow.clockwise", tint: BX.muted) { Task { await model.refresh(force: true) } },
        ] + (model.googleConfigured ? [model.account == nil
            ? Item(id: "google", title: "Sign in with Google", keys: "", icon: "person.crop.circle.badge.plus", tint: Color(hex: 0x8FB0F2)) { Task { await model.signInWithGoogle() } }
            : Item(id: "import", title: "Import from YouTube", keys: "", icon: "square.and.arrow.down", tint: Color(hex: 0x8FB0F2)) { Task { await model.importFromYouTube() } }] : [])
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
