import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

/// Glass used by the island pieces in the mockup: rgba(30,30,34,.72) over a 28 pt blur, 1 pt white/12% border,
/// soft drop shadow and a faint top highlight. Over full-screen media it's clearer (rgba(18,18,22,.42)).
struct IslandGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var onMedia: Bool
    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(onMedia ? Color(hex: 0x121216, opacity: 0.42) : Color(hex: 0x1E1E22, opacity: 0.72)))
            }
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .overlay(alignment: .top) {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
    }
}

extension View {
    func islandGlass<S: InsettableShape>(_ shape: S, onMedia: Bool = false) -> some View {
        modifier(IslandGlass(shape: shape, onMedia: onMedia))
    }
}

/// The floating island (Island.dc.html): five tabs + search orb, and the mini player docked on top while something plays.
/// Gestures (idea 04): swipe across it to scrub, long-press the mini player for the chapter ring, swipe up for commands.
struct Island: View {
    @Environment(AppModel.self) private var model
    var onMedia: Bool
    @State private var scrubTime: Double?
    @State private var scrubStart: Double = 0
    @State private var newCount = 0

    var body: some View {
        VStack(spacing: 8) {
            if let video = model.player.video, !onMedia, model.watching == nil, !model.showMusicPlayer, !model.showChapterRing {
                if let t = scrubTime {
                    ScrubIsland(video: video, time: t).transition(.blurReplace)
                } else {
                    MiniPlayer(video: video).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            HStack(spacing: 10) {
                tabs
                Button { withAnimation(.smooth) { model.showCommandPanel = true } } label: {
                    IconView(.search, size: 22, lineWidth: 2)
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .islandGlass(Circle(), onMedia: onMedia)
                .accessibilityLabel("Search")
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20).onEnded { v in
                    if v.translation.height < -40, abs(v.translation.width) < 60 {
                        withAnimation(.smooth) { model.showCommandPanel = true }
                    }
                }
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 34)
        .padding(.bottom, 22)
        .background {
            if !onMedia {
                LinearGradient(stops: [
                    .init(color: BX.ground.opacity(0), location: 0),
                    .init(color: BX.ground.opacity(0.85), location: 0.45),
                    .init(color: BX.ground.opacity(0.96), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            }
        }
        .animation(.smooth(duration: 0.3), value: model.player.video?.id)
        .animation(.smooth(duration: 0.25), value: scrubTime == nil)
        .simultaneousGesture(scrubGesture)
        .observing(model.store, { db in try Q.subscriptions(db).reduce(0) { $0 + $1.newCount } }) { newCount = $0 }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, tab in
                if i > 0 { Spacer(minLength: 0) }
                tabButton(tab)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .islandGlass(Capsule(), onMedia: onMedia)
    }

    private func tabButton(_ tab: Tab) -> some View {
        let active = model.tab == tab
        let fg: Color = active ? activeTint : (onMedia ? .white : Color(hex: model.calmMode ? 0xA8AAA6 : 0xC7C7CC))
        return Button {
            if model.tab == tab { model.paths[tab] = [] }
            withAnimation(.snappy(duration: 0.3)) { model.tab = tab }
        } label: {
            HStack(spacing: tab == .you ? 6 : 5) {
                switch tab {
                case .home: IconView(.home, size: 22)
                case .shorts: IconView(.shorts, size: 22)
                case .subs: IconView(.subs, size: 22)
                case .playlists: IconView(.playlists, size: 22)
                case .you:
                    MyAvatar(size: 26)
                        .overlay(Circle().strokeBorder(active ? activeTint : .clear, lineWidth: 2))
                }
                if active {
                    Text(tab == .you ? "You" : tab.title)
                        .font(.system(size: 12.5, weight: .semibold)).kerning(-0.125)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .foregroundStyle(fg)
            .padding(.horizontal, active ? 12 : 0)
            .frame(minWidth: 44)
            .frame(height: 48)
            .background(active ? activeTint.opacity(0.2) : .clear, in: Capsule())
            .overlay(alignment: .topTrailing) {
                if tab == .subs, !active, !model.calmMode, newCount > 0 {
                    Circle().fill(BX.coral).frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Color(hex: 0x1A1A1E), lineWidth: 2))
                        .offset(x: -7, y: 9)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab == .subs ? "Subscriptions" : (tab == .you ? "You" : tab.title))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var activeTint: Color { model.calmMode ? BX.sageText : BX.coralText }

    // Horizontal drag on the island area while something plays → scrub.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { v in
                guard model.player.video != nil, !onMedia, abs(v.translation.width) > abs(v.translation.height) * 1.4 else { return }
                if scrubTime == nil { scrubStart = model.player.state.time }
                let d = max(model.player.state.duration, 1)
                scrubTime = max(0, min(d, scrubStart + Double(v.translation.width / 300) * d * 0.5))
            }
            .onEnded { _ in
                if let t = scrubTime { model.player.seek(to: t) }
                scrubTime = nil
            }
    }
}

/// Mini player docked on the island: 58 pt tall, 22 pt corners, 66 × 40 video, pause + next, 2 pt progress line.
private struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    var video: Video

    var body: some View {
        let s = model.player.state
        HStack(spacing: 10) {
            PlayerSurface(engine: model.player)
                .frame(width: 66, height: 40)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 0) {
                Text(video.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                Text("\(video.channelTitle) · \(Format.clock(s.remaining)) left").font(.system(size: 12)).foregroundStyle(BX.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { model.player.toggle() } label: {
                Image(systemName: s.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18)).foregroundStyle(.white).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(s.isPlaying ? "Pause" : "Play")
            Button { model.advanceQueue() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 17)).foregroundStyle(.white).frame(width: 40, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next")
        }
        .padding(.leading, 8).padding(.trailing, 6)
        .frame(height: 58)
        .overlay(alignment: .bottomLeading) {
            GeometryReader { g in BX.coral.frame(width: g.size.width * s.progress, height: 2).frame(maxHeight: .infinity, alignment: .bottom) }
        }
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .islandGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture {
            if model.mode == .music { model.showMusicPlayer = true } else { model.watching = video }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            guard !video.chapters.isEmpty else { model.flash("No chapters in this video"); return }
            withAnimation(.smooth) { model.showChapterRing = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing: \(video.title)")
        .accessibilityAction(named: "Open player") { model.watching = video }
        .accessibilityAction(named: "Chapters") { model.showChapterRing = true }
    }
}

/// Idea 04a: the island becomes a scrubber with a frame preview above the finger.
private struct ScrubIsland: View {
    @Environment(AppModel.self) private var model
    var video: Video
    var time: Double

    var body: some View {
        let d = max(model.player.state.duration, 1)
        let chapters = video.chapters
        VStack(spacing: 10) {
            ScrubPreview(video: video, time: time, chapter: Chapter.current(in: chapters, at: time))
            HStack(spacing: 8) {
                Text(Format.clock(time)).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(BX.coralText).frame(width: 52, alignment: .leading)
                ZStack(alignment: .leading) {
                    ChapterBar(chapters: chapters, position: time, duration: d, height: 6)
                    GeometryReader { geo in
                        Circle().fill(.white).frame(width: 22, height: 22)
                            .shadow(color: .black.opacity(0.5), radius: 4)
                            .position(x: geo.size.width * CGFloat(time / d), y: geo.size.height / 2)
                    }
                }
                .frame(height: 24)
                Text(Format.clock(d)).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(BX.muted).frame(width: 52, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .boxGlass(Capsule(), tint: BX.coral.opacity(0.15))
            .overlay(Capsule().strokeBorder(BX.coral.opacity(0.5)))
        }
        .accessibilityElement()
        .accessibilityLabel("Scrubbing to \(Format.clock(time))")
    }
}

/// Idea 04b: long-press the mini player → chapters fan out in an arc. Tap (or slide to) one to jump.
struct ChapterRing: View {
    @Environment(AppModel.self) private var model
    @State private var hovered: Int?

    var body: some View {
        if let video = model.player.video {
            let chapters = video.chapters
            let current = Chapter.current(in: chapters, at: model.player.state.time)?.index ?? 0
            let selected = hovered ?? current
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height - 92)
                let radius = min(geo.size.width * 0.42, 170)
                ZStack {
                    Rectangle().fill(.black.opacity(0.55)).background(.ultraThinMaterial).ignoresSafeArea()
                        .onTapGesture { close() }
                    if chapters.indices.contains(selected) {
                        let c = chapters[selected]
                        VStack(spacing: 4) {
                            Text("CHAPTER \(selected + 1) OF \(chapters.count)").font(.system(size: 11, weight: .heavy)).kerning(1).foregroundStyle(BX.coralText)
                            Text(c.title).font(BX.display(26, .bold)).multilineTextAlignment(.center).lineLimit(2)
                            Text("Starts at \(Format.clock(c.start)) · \(Format.minutes(c.length))").font(.system(size: 13)).foregroundStyle(BX.text2)
                        }
                        .padding(.horizontal, 30)
                        .position(x: center.x, y: center.y - radius - 110)
                    }
                    ForEach(chapters) { c in
                        let angle = angleFor(c.index, count: chapters.count)
                        let p = CGPoint(x: center.x + radius * cos(angle), y: center.y - radius * sin(angle))
                        let isSel = c.index == selected
                        Button { jump(to: c) } label: {
                            ArtView(seed: video.id + "\(c.index)", title: c.title, word: String(format: "%02d", c.index + 1), palette: ArtPalette.forSeed(video.id))
                                .frame(width: isSel ? 80 : 60, height: isSel ? 80 : 60)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(isSel ? BX.coral : .white.opacity(0.2), lineWidth: isSel ? 3 : 1))
                                .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
                        }
                        .buttonStyle(.plain)
                        .position(p)
                        .accessibilityLabel("Chapter \(c.index + 1), \(c.title)")
                    }
                    HStack(spacing: 12) {
                        PlayerSurface(engine: model.player).frame(width: 66, height: 44).clipShape(.rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(video.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                            Text("Slide to a chapter, let go to jump").font(.system(size: 12)).foregroundStyle(BX.muted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 64)
                    .boxGlass(Capsule())
                    .padding(.horizontal, 14)
                    .position(x: geo.size.width / 2, y: center.y)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    hovered = nearest(to: v.location, center: center, radius: radius, count: chapters.count)
                }.onEnded { _ in
                    if let h = hovered, chapters.indices.contains(h) { jump(to: chapters[h]) }
                })
            }
            .animation(.snappy, value: selected)
        }
    }

    private func angleFor(_ i: Int, count: Int) -> CGFloat {
        let spread = CGFloat.pi * 0.7
        let start = CGFloat.pi / 2 + spread / 2
        return count <= 1 ? .pi / 2 : start - spread * CGFloat(i) / CGFloat(count - 1)
    }

    private func nearest(to point: CGPoint, center: CGPoint, radius: CGFloat, count: Int) -> Int? {
        guard count > 0, point.y < center.y - 20 else { return nil }
        var best: (Int, CGFloat)?
        for i in 0..<count {
            let a = angleFor(i, count: count)
            let p = CGPoint(x: center.x + radius * cos(a), y: center.y - radius * sin(a))
            let d = hypot(p.x - point.x, p.y - point.y)
            if best == nil || d < best!.1 { best = (i, d) }
        }
        return best.flatMap { $0.1 < 90 ? $0.0 : nil }
    }

    private func jump(to c: Chapter) {
        model.player.seek(to: c.start)
        close()
    }

    private func close() { withAnimation(.smooth) { model.showChapterRing = false; hovered = nil } }
}
