import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

// MARK: - Music home

struct MusicHomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var playlists: [PlaylistSummary] = []
    @State private var artists: [Q.SubscriptionRow] = []
    @State private var feed: [Video] = []
    @State private var liked: [Video] = []
    @State private var filter = "All"

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    BrandMark()
                    Spacer()
                    ModeSwitch()
                    Spacer()
                    CircleIconButton("bell", label: "Notifications") { model.tab = .subs }
                }
                .padding(.leading, 20).padding(.trailing, 16).padding(.top, 6)

                LargeTitle(greeting, size: 28).padding(.horizontal, 20).padding(.top, 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["All", "Mixes", "Playlists", "Artists"], id: \.self) { f in
                            Chip(f, selected: filter == f) { withAnimation(.snappy) { filter = f } }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 12)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(quickPicks.prefix(6)) { q in
                        Button { q.play() } label: {
                            HStack(spacing: 10) {
                                q.art.frame(width: 56, height: 56).clipped()
                                Text(q.title).font(.system(size: 13, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                    .foregroundStyle(q.isPlaying ? BX.coralText : BX.text)
                                Spacer(minLength: 0)
                                if q.isPlaying { EqualizerBars(animating: model.player.state.isPlaying).padding(.trailing, 10) }
                            }
                            .frame(height: 56)
                            .background(BX.surface2)
                            .clipShape(.rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 16)

                if filter == "All" || filter == "Mixes" {
                    SectionHeader("Mixed for you").padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 12)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(Array(artists.prefix(6).enumerated()), id: \.element.id) { i, a in
                                let mix = feed.filter { $0.channelId == a.channel.id }
                                Button { playAll(mix.shuffled()) } label: {
                                    MixCover(title: "Mix \(i + 1)", seed: a.channel.id, subtitle: ([a.channel.title] + artists.filter { $0.id != a.id }.prefix(1).map(\.channel.title)).joined(separator: ", ") + " and more")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                if filter == "All" || filter == "Artists" {
                    SectionHeader("New from your artists").padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 12)
                    VStack(spacing: 14) {
                        ForEach(feed.prefix(12)) { v in
                            VideoRow(video: v, thumbWidth: 120) { model.open(v) }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                if artists.isEmpty {
                    HintCard(icon: "music.note", title: "No music channels yet", message: "Subscribe to a channel while in Music mode and it shows up here.").padding(16)
                }
            }
        }
        .islandClearance()
        .refreshable { await model.refresh(force: true) }
        .observing(model.store, { db in try Q.playlists(db, music: true) }) { playlists = $0 }
        .observing(model.store, { db in try Q.subscriptions(db, music: true) }) { artists = $0 }
        .observing(model.store, { db in try Q.feed(db, music: true, limit: 80) }) { feed = $0 }
        .observing(model.store, { db in try Q.liked(db, music: true) }) { liked = $0 }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        return h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
    }

    struct QuickPick: Identifiable {
        var id: String
        var title: String
        var art: AnyView
        var isPlaying: Bool
        var play: () -> Void
    }

    private var quickPicks: [QuickPick] {
        var picks: [QuickPick] = []
        let playingChannel = model.player.video?.channelId
        if !liked.isEmpty {
            picks.append(QuickPick(id: "liked", title: "Liked music", art: AnyView(ZStack { BX.coral; Image(systemName: "heart.fill").foregroundStyle(BX.cream) }), isPlaying: false) { playAll(liked) })
        }
        for p in playlists {
            picks.append(QuickPick(id: p.id, title: p.playlist.title, art: AnyView(ArtView(seed: p.id, title: p.playlist.title, showWord: false)), isPlaying: false) {
                Task {
                    let vids = (try? await model.store.read { [id = p.id] db in try Q.playlistVideos(db, id: id) }) ?? []
                    if vids.isEmpty { model.push(.playlist(p.id)) } else { playAll(vids) }
                }
            })
        }
        for a in artists {
            picks.append(QuickPick(id: a.id, title: a.channel.title, art: AnyView(ChannelAvatarSquare(title: a.channel.title, url: a.channel.avatarURL)), isPlaying: playingChannel == a.channel.id) {
                playAll(feed.filter { $0.channelId == a.channel.id })
            })
        }
        return picks
    }

    private func playAll(_ videos: [Video]) {
        guard let first = videos.first else { return }
        model.player.queue = Array(videos.dropFirst())
        model.open(first)
    }
}

struct ChannelAvatarSquare: View {
    var title: String
    var url: URL?
    var body: some View {
        ZStack {
            ArtView(seed: title, title: title, showWord: false)
            ChannelAvatar(title: title, url: url, size: 56).scaleEffect(1.42)
        }
        .clipped()
    }
}

struct MixCover: View {
    var title: String
    var seed: String
    var subtitle: String
    var size: CGFloat = 148
    var body: some View {
        let palette = ArtPalette.forSeed(seed)
        VStack(alignment: .leading, spacing: 0) {
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(palette.circle.opacity(0.35)).frame(height: 5).padding(.horizontal, 14)
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(palette.circle.opacity(0.65)).frame(height: 5).padding(.horizontal, 7)
            ArtView(seed: seed, title: title, word: title.uppercased(), palette: palette)
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.top, 8)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(BX.muted).lineLimit(2).padding(.top, 2)
        }
        .frame(width: size)
    }
}

// MARK: - Now playing

struct MusicPlayerScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showVideo = false
    @State private var shuffle = false
    @State private var repeatOne = false
    @State private var showQueue = false
    @State private var screen: CGSize = CGSize(width: 390, height: 844)

    /// Square art that leaves room for the controls on short screens.
    private var artSize: CGFloat { max(160, min(342, screen.width - 48, screen.height - 470)) }

    var body: some View {
        let s = model.player.state
        let ground = model.palette == .standard ? Color(hex: 0x1E1126) : model.palette.surface
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { IconView(.chevronDown, size: 24, lineWidth: 2.2).frame(width: 40, height: 40) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Minimise")
                Spacer()
                VStack(spacing: 1) {
                    Text("PLAYING FROM").font(.system(size: 10.5, weight: .bold)).kerning(0.84).foregroundStyle(.white.opacity(0.7))
                    Text(model.player.video?.channelTitle ?? "").font(.system(size: 13.5, weight: .bold)).lineLimit(1)
                }
                Spacer()
                Menu {
                    if let v = model.player.video {
                        Button { model.toggleLike(v.id) } label: { Label(model.likedIds.contains(v.id) ? "Unlike" : "Like", systemImage: "heart") }
                        Button { model.toggleWatchLater(v.id) } label: { Label("Save to Watch later", systemImage: "clock") }
                        ShareLink(item: v.watchURL) { Label("Share", systemImage: "square.and.arrow.up") }
                        Button { model.showMusicPlayer = false; model.mode = .videos; model.watching = v } label: { Label("Watch the music video", systemImage: "play.rectangle") }
                    }
                } label: {
                    MoreDots(size: 20).frame(width: 40, height: 40).contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .accessibilityLabel("More options")
            }
            .padding(.horizontal, 16)

            HStack(spacing: 0) {
                ForEach([false, true], id: \.self) { video in
                    Button { withAnimation(.smooth) { showVideo = video } } label: {
                        Text(video ? "Video" : "Song")
                            .font(.system(size: 12.5, weight: showVideo == video ? .bold : .semibold))
                            .foregroundStyle(showVideo == video ? .white : .white.opacity(0.7))
                            .padding(.horizontal, 16).frame(height: 26)
                            .background(showVideo == video ? .white.opacity(0.18) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(showVideo == video ? .isSelected : [])
                }
            }
            .padding(3)
            .background(.black.opacity(0.3), in: Capsule())
            .padding(.top, 10)

            Group {
                if showVideo {
                    PlayerSurface(engine: model.player).aspectRatio(16 / 9, contentMode: .fit)
                } else {
                    // Song view still shows the video (YouTube's terms), cropped square like album art.
                    PlayerSurface(engine: model.player).aspectRatio(16 / 9, contentMode: .fill)
                        .frame(width: artSize, height: artSize).clipped()
                        .allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
            .padding(.horizontal, 24).padding(.top, 18)
            .animation(.smooth, value: showVideo)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.player.video?.title ?? "").font(.system(size: 21, weight: .bold)).lineLimit(1)
                    Text(model.player.video?.channelTitle ?? "").font(.system(size: 15)).foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                if let id = model.player.video?.id {
                    Button { model.toggleLike(id) } label: {
                        Image(systemName: model.likedIds.contains(id) ? "heart.fill" : "heart").font(.system(size: 25))
                            .foregroundStyle(model.likedIds.contains(id) ? BX.coral : .white).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.likedIds.contains(id) ? "Liked" : "Like")
                }
            }
            .padding(.horizontal, 24).padding(.top, 22)

            VStack(spacing: 6) {
                ChapterScrubber(chapters: [], tint: .white, showsPreview: false)
                HStack {
                    Text(Format.clock(s.time)); Spacer(); Text("−" + Format.clock(s.remaining))
                }
                .font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 24).padding(.top, 10)

            HStack {
                Button { shuffle.toggle(); if shuffle { model.player.queue.shuffle() } } label: { Image(systemName: "shuffle").font(.system(size: 20, weight: .semibold)).foregroundStyle(shuffle ? BX.coralText : .white.opacity(0.75)) }
                    .accessibilityLabel("Shuffle")
                Spacer()
                Button { model.player.seek(to: 0) } label: { Image(systemName: "backward.end.fill").font(.system(size: 28)) }
                    .accessibilityLabel("Previous")
                Spacer()
                Button { model.player.toggle() } label: {
                    Image(systemName: s.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 28)).foregroundStyle(ground)
                        .frame(width: 68, height: 68).background(.white, in: Circle())
                }
                .accessibilityLabel(s.isPlaying ? "Pause" : "Play")
                Spacer()
                Button { model.advanceQueue() } label: { Image(systemName: "forward.end.fill").font(.system(size: 28)) }
                    .accessibilityLabel("Next")
                Spacer()
                Button { repeatOne.toggle() } label: { Image(systemName: "repeat.1").font(.system(size: 20, weight: .semibold)).foregroundStyle(repeatOne ? BX.coralText : .white.opacity(0.75)) }
                    .accessibilityLabel("Repeat")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 26).padding(.top, 8)

            HStack {
                CastButton(size: 40, fill: .clear)
                Spacer()
                if let v = model.player.video {
                    Button { openURL(v.musicURL) } label: {
                        HStack(spacing: 7) {
                            Text("Continue in YouTube Music").font(.system(size: 12.5, weight: .semibold))
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 14).frame(height: 34).background(.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { showQueue = true } label: { IconView(.playlists, size: 20, lineWidth: 2).frame(width: 40, height: 40) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Queue")
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 24).padding(.top, 10)
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 8) {
                Text("Lyrics").font(.system(size: 15, weight: .bold))
                Text("Lyrics need a licensed provider, so Boxtube doesn't show them. They're in YouTube Music.")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color(hex: 0x6B3A7A).opacity(0.7), in: .rect(cornerRadius: 20))
            .padding(.horizontal, 12)
        }
        .foregroundStyle(.white)
        .background(ground.ignoresSafeArea())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
        .onChange(of: s.ended) { _, ended in
            if ended, repeatOne { model.player.seek(to: 0); model.player.play() }
        }
        .sheet(isPresented: $showQueue) {
            NavigationStack {
                List {
                    ForEach(model.player.queue) { v in
                        Button { model.open(v, present: false) } label: { Text(v.title) }
                    }
                    .onDelete { model.player.queue.remove(atOffsets: $0) }
                    .onMove { model.player.queue.move(fromOffsets: $0, toOffset: $1) }
                }
                .navigationTitle("Up next")
                .toolbar { EditButton() }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Library

struct MusicLibraryScreen: View {
    @Environment(AppModel.self) private var model
    @State private var filter = "Playlists"
    @State private var playlists: [PlaylistSummary] = []
    @State private var artists: [Q.SubscriptionRow] = []
    @State private var liked: [Video] = []
    @State private var showNew = false
    @State private var newTitle = ""
    @State private var musicVideos: [Video] = []
    @State private var recent = true
    @State private var grid = false

    struct Item: Identifiable {
        var id: String
        var title: String
        var meta: String
        var pinned = false
        var round = false
        var art: AnyView
        var action: () -> Void
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    ProfileAvatar(size: 34)
                    LargeTitle("Your library", size: 26)
                    Spacer()
                    Button { withAnimation(.smooth) { model.showCommandPanel = true } } label: { IconView(.search, size: 21, lineWidth: 2).frame(width: 40, height: 40) }
                        .buttonStyle(.plain).accessibilityLabel("Search library")
                    Button { showNew = true } label: { IconView(.plus, size: 22, lineWidth: 2).frame(width: 40, height: 40) }
                        .buttonStyle(.plain).accessibilityLabel("New playlist")
                }
                .padding(.leading, 20).padding(.trailing, 12).frame(height: 48).padding(.top, 6)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["Playlists", "Songs", "Artists", "Music videos"], id: \.self) { f in
                            Button { filter = f } label: {
                                Text(f).font(.system(size: 13, weight: filter == f ? .bold : .semibold))
                                    .padding(.horizontal, 14).frame(height: 32)
                                    .foregroundStyle(filter == f ? BX.coralText : BX.text2)
                                    .background(filter == f ? BX.coral.opacity(0.18) : BX.surface2, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 12)

                HStack {
                    Button { recent.toggle() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 13, weight: .semibold))
                            Text(recent ? "Recently played" : "Alphabetical").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(BX.text2)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { withAnimation(.snappy) { grid.toggle() } } label: {
                        Image(systemName: grid ? "list.bullet" : "square.grid.2x2").font(.system(size: 16, weight: .medium)).foregroundStyle(BX.muted)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(grid ? "Show as list" : "Show as grid")
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 6)

                if grid {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                        ForEach(items) { i in
                            Button(action: i.action) {
                                VStack(alignment: .leading, spacing: 6) {
                                    i.art.aspectRatio(1, contentMode: .fit)
                                        .clipShape(i.round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 14)))
                                    Text(i.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                    Text(i.meta).font(.system(size: 12)).foregroundStyle(BX.muted).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 4) {
                        ForEach(items) { i in
                            libraryRow(title: i.title, meta: i.meta, pinned: i.pinned, round: i.round, art: i.art, action: i.action)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .islandClearance()
        .alert("New playlist", isPresented: $showNew) {
            TextField("Name", text: $newTitle)
            Button("Create") { let t = newTitle; newTitle = ""; Task { try? await model.store.createPlaylist(title: t.isEmpty ? "New playlist" : t, music: true) } }
            Button("Cancel", role: .cancel) {}
        }
        .observing(model.store, { db in try Q.playlists(db, music: true) }) { playlists = $0 }
        .observing(model.store, { db in try Q.subscriptions(db, music: true) }) { artists = $0 }
        .observing(model.store, { db in try Q.liked(db, music: true) }) { liked = $0 }
        .observing(model.store, { db in try Q.feed(db, music: true, limit: 40) }) { musicVideos = $0 }
    }

    private var items: [Item] {
        var list: [Item] = []
        switch filter {
        case "Playlists":
            if !liked.isEmpty {
                list.append(Item(id: "liked", title: "Liked music", meta: "Playlist · \(liked.count) songs", pinned: true,
                                 art: AnyView(ZStack { BX.coral; Image(systemName: "heart.fill").foregroundStyle(BX.cream) })) { model.push(.liked) })
            }
            list += playlists.map { p in
                Item(id: p.id, title: p.playlist.title, meta: "Playlist · \(p.count) songs",
                     art: AnyView(ArtView(seed: p.id, title: p.playlist.title, showWord: false))) { model.push(.playlist(p.id)) }
            }
        case "Songs":
            list = liked.map { v in Item(id: v.id, title: v.title, meta: v.channelTitle, art: AnyView(VideoThumbnail(v, radius: 0, showDuration: false, aspect: 1))) { model.open(v) } }
        case "Artists":
            list = artists.map { a in
                Item(id: a.id, title: a.channel.title, meta: "Artist", round: true, art: AnyView(ChannelAvatarSquare(title: a.channel.title, url: a.channel.avatarURL))) { model.push(.channel(a.channel.id)) }
            }
        default:
            list = musicVideos.map { v in Item(id: v.id, title: v.title, meta: v.channelTitle, art: AnyView(VideoThumbnail(v, radius: 0, showDuration: false, aspect: 1))) { model.open(v) } }
        }
        return recent ? list : list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func libraryRow(title: String, meta: String, pinned: Bool = false, round: Bool = false, art: AnyView, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                art.frame(width: 56, height: 56).clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        if pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(BX.coral) }
                        Text(meta).font(.system(size: 12.5)).foregroundStyle(BX.muted)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8).frame(height: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
