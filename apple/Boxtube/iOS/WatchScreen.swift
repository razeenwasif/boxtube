import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

/// Watch screen laid out to the "iOS · Watch" artboard.
struct WatchScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var video: Video
    @State private var current: Video?
    @State private var channel: Channel?
    @State private var upNext: [Video] = []
    @State private var notes: [Note] = []
    @State private var playlists: [PlaylistSummary] = []
    @State private var comment: YouTubeClient.TopComment?
    @State private var controlsVisible = true
    @State private var dragOffset: CGFloat = 0
    @State private var pinching = false
    @State private var expanded = false
    @State private var showNotes = false
    @State private var disliked = false
    @State private var together = WatchTogether.shared

    var body: some View {
        let v = current ?? video
        let chapters = v.chapters
        VStack(spacing: 0) {
            player(v, chapters: chapters)
            if together.isActive { TogetherBanner(together: together).padding(.horizontal, 12).padding(.top, 10) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock(v)
                    channelRow(v)
                    actions(v)
                    if expanded, !v.summary.isEmpty {
                        Text(v.summary).font(.system(size: 13.5)).foregroundStyle(BX.text2).textSelection(.enabled)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                    }
                    if !chapters.isEmpty { chaptersCard(chapters) }
                    commentsCard(v)
                    if !notes.isEmpty { notesCard }
                    if together.isActive { VoteCard(together: together, candidates: Array(upNext.prefix(2))) }
                    if !model.userQueue.isEmpty {
                        QueuePanel(thumbWidth: 104).cardSurface()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Up next").font(.system(size: 17, weight: .bold)).accessibilityAddTraits(.isHeader)
                        ForEach(upNext) { n in upNextCard(n) }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16).padding(.top, 14)
                .padding(.bottom, together.isActive ? 100 : 30)
            }
        }
        .background(BX.ground)
        .overlay(alignment: .bottom) {
            if together.isActive { ReactionBar(together: together).padding(.horizontal, 14).padding(.bottom, 8) }
        }
        .offset(y: dragOffset)
        .sheet(isPresented: Binding(get: { model.showSkim }, set: { model.showSkim = $0 })) {
            SkimView(video: v).environment(model).presentationDetents([.large])
        }
        .sheet(isPresented: $showNotes) {
            NotesPanel(video: v).environment(model).presentationDetents([.medium, .large]).presentationBackground(BX.surface)
        }
        .onAppear { current = model.player.video ?? video }
        .onChange(of: model.player.video?.id) { _, _ in if let pv = model.player.video { current = pv } }
        .observing(model.store, id: v.channelId, { [cid = v.channelId] db in try Channel.fetchOne(db, key: cid) }) { channel = $0 }
        .observing(model.store, id: v.id, { [cid = v.channelId, vid = v.id] db in
            let same = try Q.channelVideos(db, channelId: cid).filter { $0.id != vid && !$0.isShort }
            let feed = try Q.feed(db, limit: 20).filter { $0.id != vid && $0.channelId != cid }
            return Array(same.prefix(4) + feed.prefix(8))
        }) { upNext = $0 }
        .observing(model.store, id: v.id, { [vid = v.id] db in try Q.notes(db, videoId: vid) }) { notes = $0 }
        .observing(model.store, { db in try Q.playlists(db) }) { playlists = $0 }
        .task(id: v.id) {
            model.player.queue = upNext
            comment = await model.feed.topComment(videoId: v.id)
        }
    }

    // MARK: Player (390 × 219 under a black status area)

    private func player(_ v: Video, chapters: [Chapter]) -> some View {
        let s = model.player.state
        return ZStack {
            PlayerSurface(engine: model.player)
            Color.black.opacity(controlsVisible ? 0.28 : 0.001)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { controlsVisible.toggle() } }
            if controlsVisible {
                // top row
                VStack {
                    HStack(spacing: 2) {
                        Button { dismiss() } label: { IconView(.chevronDown, size: 22, lineWidth: 2.2).frame(width: 36, height: 36) }
                            .accessibilityLabel("Minimise")
                        Spacer()
                        Button { model.player.setCaptions(!model.player.captionsOn) } label: {
                            Image(systemName: model.player.captionsOn ? "captions.bubble.fill" : "captions.bubble").font(.system(size: 18)).frame(width: 36, height: 36)
                        }
                        .accessibilityLabel(model.player.captionsOn ? "Turn off captions" : "Turn on captions")
                        CastButton(size: 36, fill: .clear)
                    }
                    .padding(.horizontal, 10).padding(.top, 10).padding(.trailing, -2)
                    Spacer()
                }
                // centre controls
                HStack(spacing: 30) {
                    Button { previous(chapters) } label: { Image(systemName: "backward.end.fill").font(.system(size: 22)).frame(width: 44, height: 44) }
                        .accessibilityLabel("Previous chapter")
                    Button { model.player.toggle() } label: {
                        Image(systemName: s.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 24))
                            .frame(width: 60, height: 60)
                            .background(.ultraThinMaterial, in: Circle())
                            .background(Color(hex: 0x0C0C10, opacity: 0.45), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.18)))
                    }
                    .accessibilityLabel(s.isPlaying ? "Pause" : "Play")
                    Button { next(chapters) } label: { Image(systemName: "forward.end.fill").font(.system(size: 22)).frame(width: 44, height: 44) }
                        .accessibilityLabel("Next chapter")
                }
                // bottom row
                VStack {
                    Spacer()
                    HStack {
                        Text("\(Format.clock(s.time)) / \(Format.clock(s.duration))")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        + Text(Chapter.current(in: chapters, at: s.time).map { " · \($0.title)" } ?? "")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Button { model.flash("Rotate your phone for full screen") } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 16, weight: .semibold)).frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Full screen")
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 14).padding(.bottom, 12)
                }
            }
            // chapter segments on the bottom edge (always visible) + knob
            VStack(spacing: 0) {
                Spacer()
                SegmentedScrubber(chapters: chapters, showKnob: controlsVisible)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(.black)
        .background(alignment: .top) { Color.black.frame(height: 200).offset(y: -200).ignoresSafeArea() }
        .gesture(DragGesture().onChanged { g in
            if !pinching, g.translation.height > 0 { dragOffset = g.translation.height * 0.6 }
        }.onEnded { g in
            if !pinching, g.translation.height > 120 { dismiss() }
            withAnimation(.snappy) { dragOffset = 0 }
        })
        // Pinch in to Skim. Runs alongside the swipe-down drag, which stands down while two fingers pinch.
        .simultaneousGesture(MagnifyGesture()
            .onChanged { _ in if !pinching { pinching = true; withAnimation(.snappy) { dragOffset = 0 } } }
            .onEnded { value in
                pinching = false
                if value.magnification < 0.8 { model.showSkim = true }
            })
        .task(id: controlsVisible) {
            guard controlsVisible, model.player.state.isPlaying else { return }
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation { controlsVisible = false }
        }
    }

    private func previous(_ chapters: [Chapter]) {
        let t = model.player.state.time
        if let c = Chapter.current(in: chapters, at: t) {
            if t - c.start > 3 || c.index == 0 { model.player.seek(to: c.start) } else { model.player.seek(to: chapters[c.index - 1].start) }
        } else { model.player.seek(to: 0) }
    }

    private func next(_ chapters: [Chapter]) {
        let t = model.player.state.time
        if let n = chapters.first(where: { $0.start > t + 1 }) { model.player.seek(to: n.start) } else { model.advanceQueue() }
    }

    // MARK: Sections

    private func titleBlock(_ v: Video) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(v.title).font(.system(size: 18, weight: .bold)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                (Text([Format.views(v.viewCount), Format.ago(v.publishedAt), hashtag(v)].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(BX.muted)
                 + Text(expanded ? "  less" : "  …more").foregroundStyle(BX.text).fontWeight(.semibold))
                    .font(.system(size: 12.5))
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
    }

    private func hashtag(_ v: Video) -> String? {
        v.summary.firstMatch(of: /#[A-Za-z0-9_]+/).map { String($0.0) }
    }

    private func channelRow(_ v: Video) -> some View {
        let subscribed = channel?.isSubscribed ?? false
        return HStack(spacing: 10) {
            Button { dismiss(); model.push(.channel(v.channelId)) } label: {
                HStack(spacing: 10) {
                    ChannelAvatar(title: v.channelTitle, url: channel?.avatarURL, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(v.channelTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if let subs = Format.count(channel?.subscriberCount) { Text("\(subs) subscribers").font(.system(size: 12)).foregroundStyle(BX.muted) }
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                if subscribed { model.unsubscribe(v.channelId) } else { model.subscribe(channel ?? Channel(id: v.channelId, title: v.channelTitle)) }
            } label: {
                Text(subscribed ? "Subscribed" : "Subscribe").font(.system(size: 13.5, weight: .bold))
                    .padding(.horizontal, 16).frame(height: 36)
                    .foregroundStyle(subscribed ? BX.text : BX.ground)
                    .background(subscribed ? BX.surface3 : BX.text, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func actions(_ v: Video) -> some View {
        let liked = model.likedIds.contains(v.id)
        let saved = model.watchLaterIds.contains(v.id)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Button { if disliked { disliked = false }; model.toggleLike(v.id) } label: {
                        Label(liked ? "Liked" : (Format.count(v.likeCount) ?? "Like"), systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(liked ? BX.coralText : BX.text)
                            .padding(.leading, 14).padding(.trailing, 12).frame(height: 36)
                    }
                    .accessibilityLabel(liked ? "Liked" : "Like")
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1).padding(.vertical, 9)
                    Button { disliked.toggle(); model.setDisliked(v.id, disliked) } label: {
                        Image(systemName: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown").font(.system(size: 14))
                            .padding(.horizontal, 13).frame(height: 36)
                    }
                    .accessibilityLabel("Dislike")
                }
                .background(Color(hex: 0x1C1C20), in: Capsule())
                ShareLink(item: v.watchURL) { PillLabel(title: "Share", icon: "square.and.arrow.up", active: false) }
                Pill(saved ? "Saved" : "Save", icon: saved ? "clock.fill" : "clock", active: saved) { model.toggleWatchLater(v.id) }
                Menu {
                    ForEach(playlists) { p in Button(p.playlist.title) { model.add(v.id, to: p.playlist) } }
                } label: { PillLabel(title: "Playlist", icon: "text.badge.plus", active: false) }
                Pill("Note", icon: "note.text.badge.plus", active: false) { showNotes = true }
                Pill("Skim", icon: "square.grid.2x2", active: false) { model.showSkim = true }
                Pill(together.isActive ? "Together" : "Watch together", icon: "shareplay", active: together.isActive) { together.start(with: v) }
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
        }
        .padding(.trailing, -16)
        .scrollClipDisabled()
    }

    private func chaptersCard(_ chapters: [Chapter]) -> some View {
        let currentIndex = Chapter.current(in: chapters, at: model.player.state.time)?.index
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Chapters").font(.system(size: 14, weight: .bold))
                Spacer()
                if let currentIndex { Text("\(currentIndex + 1) of \(chapters.count)").font(.system(size: 12)).foregroundStyle(BX.muted) }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chapters) { c in
                            let on = c.index == currentIndex
                            Button { model.player.seek(to: c.start) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Format.clock(c.start)).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(on ? BX.coralText : BX.muted)
                                    Text(c.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(on ? BX.coral.opacity(0.12) : Color(hex: 0x1C1C20), in: .rect(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(on ? BX.coral.opacity(0.45) : .white.opacity(0.04)))
                            }
                            .buttonStyle(.plain)
                            .id(c.index)
                        }
                    }
                    .padding(.trailing, 14)
                }
                .padding(.trailing, -14)
                .onChange(of: currentIndex) { _, i in if let i { withAnimation { proxy.scrollTo(i, anchor: .center) } } }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .cardSurface()
    }

    private func commentsCard(_ v: Video) -> some View {
        Button { openURL(v.watchURL) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Comments").font(.system(size: 14, weight: .bold))
                    if let total = Format.count(comment?.total) { Text(total).font(.system(size: 12.5)).foregroundStyle(BX.muted) }
                    Spacer()
                }
                HStack(alignment: .top, spacing: 10) {
                    if let comment {
                        ChannelAvatar(title: comment.author, size: 26)
                        Text(comment.text).font(.system(size: 13)).foregroundStyle(BX.text2).lineSpacing(2).lineLimit(2).multilineTextAlignment(.leading)
                    } else {
                        Text(model.hasAPIKey ? "Loading comments…" : "Read and join the conversation on YouTube.")
                            .font(.system(size: 13)).foregroundStyle(BX.muted)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    private var notesCard: some View {
        Button { showNotes = true } label: {
            HStack {
                Image(systemName: "note.text").foregroundStyle(BX.amber)
                Text("\(notes.count) notes on this video").font(.system(size: 14, weight: .semibold))
                Spacer()
                IconView(.chevronRight, size: 16, lineWidth: 2.2).foregroundStyle(BX.dim)
            }
            .padding(14).cardSurface()
        }
        .buttonStyle(.plain)
    }

    private func upNextCard(_ n: Video) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.open(n, present: false); current = n } label: {
                VideoThumbnail(n, radius: 18, inset: 10)
            }
            .buttonStyle(.plain)
            HStack(alignment: .top, spacing: 4) {
                Button { model.open(n, present: false); current = n } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.title).font(.system(size: 14.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Text([n.channelTitle, Format.views(n.viewCount), Format.ago(n.publishedAt)].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(BX.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                VideoMoreButton(video: n, size: 18).padding(.top, -6)
            }
            .padding(.horizontal, 2)
        }
        .videoContextMenu(n)
    }
}

/// Chapter segments along the player's bottom edge (gap 2, 4 pt tall) with a coral knob; drag to scrub.
private struct SegmentedScrubber: View {
    @Environment(AppModel.self) private var model
    var chapters: [Chapter]
    var showKnob: Bool
    @State private var scrub: Double?

    var body: some View {
        let s = model.player.state
        let d = max(s.duration, 1)
        let t = scrub ?? s.time
        GeometryReader { geo in
            let segments = chapters.isEmpty ? [Chapter(index: 0, title: "", start: 0, end: d)] : chapters
            let gap: CGFloat = segments.count > 1 ? 2 : 0
            let usable = geo.size.width - gap * CGFloat(segments.count - 1)
            ZStack(alignment: .bottomLeading) {
                HStack(spacing: gap) {
                    ForEach(segments) { c in
                        let w = max(1, usable * CGFloat(c.length / d))
                        let fill = c.length > 0 ? min(1, max(0, (t - c.start) / c.length)) : 0
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.3))
                            Rectangle().fill(BX.coral).frame(width: w * fill)
                        }
                        .frame(width: w, height: 4)
                    }
                }
                if showKnob || scrub != nil {
                    Circle().fill(BX.coral).frame(width: 14, height: 14)
                        .offset(x: geo.size.width * CGFloat(t / d) - 7, y: 5)
                }
            }
            .frame(height: geo.size.height, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                scrub = max(0, min(d, Double(g.location.x / geo.size.width) * d))
            }.onEnded { _ in
                if let scrub { model.player.seek(to: scrub) }
                scrub = nil
            })
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Format.clock(s.time)) of \(Format.clock(s.duration))")
        .accessibilityAdjustableAction { dir in model.player.skip(dir == .increment ? 10 : -10) }
    }
}

extension View {
    /// Card from the mockups: #151518, 16 pt corners, 6% white hairline.
    func cardSurface(_ radius: CGFloat = 16) -> some View {
        background(Color(hex: 0x151518), in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

struct Pill: View {
    var title: String
    var icon: String
    var active: Bool
    var action: () -> Void
    init(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.active = active; self.action = action
    }
    var body: some View {
        Button(action: action) { PillLabel(title: title, icon: icon, active: active) }
    }
}

struct PillLabel: View {
    var title: String
    var icon: String
    var active: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
            Text(title).font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 14).frame(height: 36)
        .foregroundStyle(active ? BX.coralText : BX.text)
        .background(active ? BX.coral.opacity(0.15) : Color(hex: 0x1C1C20), in: Capsule())
    }
}
