import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

// Screens laid out to the iOS artboards on the design canvas (iOSShorts, iOSSubscriptions, iOSPlaylists, iOSProfile).

// MARK: - Shorts (iOS · Shorts)

struct ShortsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var shorts: [Video] = []
    @State private var current: String?
    @State private var forYou = true

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(shorts) { s in
                            ShortPage(video: s, isCurrent: current == s.id && model.tab == .shorts)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(s.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $current)
                .scrollIndicators(.hidden)
            }
            .ignoresSafeArea()

            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            HStack(spacing: 22) {
                feedTab("Following", selected: !forYou) { forYou = false }
                feedTab("For you", selected: forYou) { forYou = true }
            }
            .frame(height: 44)
            .padding(.top, 4)

            if shorts.isEmpty {
                HintCard(icon: "play.rectangle.on.rectangle", title: "No Shorts yet", message: "Shorts from channels you follow show up here after the next refresh.")
                    .padding(20)
                    .frame(maxHeight: .infinity)
            }
        }
        .background(.black)
        .observing(model.store, id: forYou, { [forYou] db in
            let all = try Q.shorts(db)
            return forYou ? all : all.sorted { $0.channelTitle < $1.channelTitle }
        }) { list in
            shorts = list
            if current == nil || !list.contains(where: { $0.id == current }) { current = list.first?.id }
        }
        .onChange(of: current) { _, id in play(id) }
        .onChange(of: model.tab) { _, tab in
            if tab == .shorts { play(current) }
            else if model.player.video?.isShort == true { model.player.stop() }
        }
    }

    private func feedTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.72))
                .frame(height: 44)
                .overlay(alignment: .bottom) {
                    if selected { RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 20, height: 3).padding(.bottom, 6) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func play(_ id: String?) {
        guard model.tab == .shorts, let id, let v = shorts.first(where: { $0.id == id }) else { return }
        if model.player.video?.id != id { model.player.load(v, at: 0) } else { model.player.play() }
    }
}

private struct ShortPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    var video: Video
    var isCurrent: Bool
    @State private var expanded = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.overlay {
                VideoThumbnail(video, radius: 0, showDuration: false, aspect: 9 / 16).scaledToFill()
            }
            .clipped()
            if isCurrent && model.player.video?.id == video.id {
                Color.clear.overlay {
                    PlayerSurface(engine: model.player).aspectRatio(9 / 16, contentMode: .fill)
                }
                .clipped()
                .allowsHitTesting(false)
            }
            Color.black.opacity(0.001).onTapGesture { model.player.toggle() }
            VStack {
                Spacer()
                LinearGradient(stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black.opacity(0.6), location: 0.55),
                    .init(color: .black.opacity(0.88), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: 420)
            }
            .allowsHitTesting(false)

            // Caption block: left 16, right 84, bottom 140
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ChannelAvatar(title: video.channelTitle, size: 36)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    Text("@" + video.channelTitle.lowercased().replacingOccurrences(of: " ", with: ""))
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    Button { model.subscribe(Channel(id: video.channelId, title: video.channelTitle)) } label: {
                        Text("Subscribe").font(.system(size: 13, weight: .bold)).foregroundStyle(BX.ground)
                            .padding(.horizontal, 14).frame(height: 30).background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button { expanded.toggle() } label: {
                    (Text(video.title) + Text(expanded ? "" : "  more").foregroundStyle(.white.opacity(0.72)).fontWeight(.semibold))
                        .font(.system(size: 14.5)).lineSpacing(3)
                        .lineLimit(expanded ? 8 : 3)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                HStack(spacing: 7) {
                    IconView(.music, size: 14, lineWidth: 2)
                    Text("Original audio · \(video.channelTitle)").font(.system(size: 13)).lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            .foregroundStyle(.white)
            .padding(.leading, 16).padding(.trailing, 84).padding(.bottom, 140)

            // Action rail: right 10, bottom 140
            VStack(spacing: 16) {
                let liked = model.likedIds.contains(video.id)
                rail(Format.count(video.likeCount) ?? "Like", label: liked ? "Liked" : "Like") {
                    IconView(.heart, size: 24, lineWidth: 1.8, fill: liked ? BX.coral : nil).foregroundStyle(liked ? BX.coral : .white)
                } action: { model.toggleLike(video.id) }
                rail("Comments", label: "Comments on YouTube") {
                    IconView(.comment, size: 23, lineWidth: 1.8)
                } action: { openURL(URL(string: "https://www.youtube.com/shorts/\(video.id)")!) }
                ShareLink(item: URL(string: "https://www.youtube.com/shorts/\(video.id)")!) {
                    railLabel("Share") { IconView(.share, size: 22, lineWidth: 1.8) }
                }
                .buttonStyle(.plain)
                let saved = model.watchLaterIds.contains(video.id)
                rail(saved ? "Saved" : "Save", label: saved ? "Saved to Watch later" : "Save to Watch later") {
                    IconView(.clock, size: 22, lineWidth: 1.8).foregroundStyle(saved ? BX.amber : .white)
                } action: { model.toggleWatchLater(video.id) }
                ChannelAvatar(title: video.channelTitle, size: 36)
                    .frame(width: 40, height: 40)
                    .background(ArtPalette.forSeed(video.channelTitle).bg, in: .rect(cornerRadius: 11))
                    .clipShape(.rect(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white, lineWidth: 2))
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 10).padding(.bottom, 140)

            // Progress line: bottom 124
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white).frame(width: g.size.width * (isCurrent ? model.player.state.progress : 0))
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 16).padding(.bottom, 124)
            .allowsHitTesting(false)
        }
        .clipped()
    }

    private func rail<Icon: View>(_ text: String, label: String, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) { railLabel(text, icon: icon) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private func railLabel<Icon: View>(_ text: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 4) {
            icon()
                .frame(width: 48, height: 48)
                .islandGlass(Circle(), onMedia: true)
            Text(text).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        .frame(width: 56)
    }
}

// MARK: - Subscriptions (iOS · Subscriptions)

struct SubscriptionsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var subs: [Q.SubscriptionRow] = []
    @State private var feed: [Video] = []
    @State private var filter = 0
    @State private var channelFilter: String?
    @State private var progress: [String: Double] = [:]
    @State private var showManage = false

    private let filters = ["All", "Today", "Live", "Unwatched"]

    var body: some View {
        let shown = filtered
        let groups = Dictionary(grouping: shown) { dayLabel($0.publishedAt) }
        let order = ["Today", "Yesterday", "This week", "Earlier"].filter { groups[$0] != nil }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenHeader("Subscriptions") {
                    CircleIconButtonView(label: "Manage subscriptions") { IconView(.sliders, size: 19, lineWidth: 1.8) } action: { showManage = true }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(subs) { row in channelBubble(row) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
                .padding(.top, 16)

                HStack(spacing: 3) {
                    ForEach(Array(filters.enumerated()), id: \.offset) { i, f in
                        Button { withAnimation(.snappy(duration: 0.2)) { filter = i } } label: {
                            Text(f)
                                .font(.system(size: 13, weight: filter == i ? .semibold : .medium))
                                .foregroundStyle(filter == i ? BX.text : BX.muted)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(filter == i ? Color(hex: 0x2A2A30) : .clear, in: .rect(cornerRadius: 9))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == i ? .isSelected : [])
                    }
                }
                .padding(3)
                .frame(height: 38)
                .background(Color(hex: 0x17171A), in: .rect(cornerRadius: 12))
                .padding(.horizontal, 16).padding(.top, 18)

                ForEach(order, id: \.self) { label in
                    Text(label).font(.system(size: 17, weight: .bold))
                        .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 12)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 16) {
                        ForEach(groups[label] ?? []) { v in
                            VideoRow(video: v, subtitle: subtitle(v), progress: progress[v.id])
                        }
                    }
                    .padding(.horizontal, 16)
                }
                if shown.isEmpty {
                    HintCard(icon: "tray", title: "All caught up", message: "Nothing matches this filter.").padding(16)
                }
            }
        }
        .islandClearance()
        .refreshable { await model.refresh(force: true) }
        .sheet(isPresented: $showManage) { ManageSubscriptionsSheet().environment(model) }
        .observing(model.store, { db in try Q.subscriptions(db) }) { subs = $0 }
        .observing(model.store, { db in try Q.feed(db, music: false, limit: 120) + Q.feed(db, music: true, limit: 30) }) { list in
            feed = list.sorted { $0.publishedAt > $1.publishedAt }
        }
        .observing(model.store, { db in try Q.progress(db) }) { progress = $0 }
        .onDisappear { Task { try? await model.store.markChannelsSeen() } }
    }

    private func channelBubble(_ row: Q.SubscriptionRow) -> some View {
        let on = channelFilter == row.channel.id
        let ring: Color = row.isLive ? BX.coral : (on ? BX.text : (row.newCount > 0 ? .white.opacity(0.22) : .clear))
        return Button { withAnimation(.snappy) { channelFilter = on ? nil : row.channel.id } } label: {
            VStack(spacing: 7) {
                ChannelAvatar(title: row.channel.title, url: row.channel.avatarURL, size: 52)
                    .padding(3)
                    .overlay(Circle().strokeBorder(ring, lineWidth: 2))
                    .frame(width: 62, height: 62)
                    .overlay(alignment: .bottom) {
                        if row.isLive {
                            Text("LIVE").font(.system(size: 9.5, weight: .heavy)).kerning(0.5).foregroundStyle(BX.coralInk)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(BX.coral, in: .rect(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(BX.ground, lineWidth: 2))
                                .offset(y: 6)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if row.newCount > 0, !row.isLive {
                            Circle().fill(BX.coral).frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(BX.ground, lineWidth: 2.5))
                                .offset(x: -1, y: 1)
                        }
                    }
                Text(row.channel.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(BX.text2)
                    .lineLimit(1).frame(width: 62)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.channel.title + (row.isLive ? ", live" : (row.newCount > 0 ? ", new videos" : "")))
        .contextMenu {
            Button { model.push(.channel(row.channel.id)) } label: { Label("Open channel", systemImage: "person.crop.square") }
            Button(role: .destructive) { model.unsubscribe(row.channel.id) } label: { Label("Unsubscribe", systemImage: "minus.circle") }
        }
    }

    private func subtitle(_ v: Video) -> String {
        [Format.views(v.viewCount), Format.ago(v.publishedAt)].compactMap { $0 }.joined(separator: " · ")
    }

    private var filtered: [Video] {
        feed.filter { v in
            (channelFilter == nil || v.channelId == channelFilter) &&
            (filter != 1 || Calendar.current.isDateInToday(v.publishedAt)) &&
            (filter != 2 || v.isLive) &&
            (filter != 3 || (progress[v.id] ?? 0) < 0.05)
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if date > .now.addingTimeInterval(-7 * 86_400) { return "This week" }
        return "Earlier"
    }
}

/// 40 pt circle button with a mockup icon.
struct CircleIconButtonView<Icon: View>: View {
    var label: String
    var size: CGFloat = 40
    var fill: Color = BX.surface2
    var tint: Color = BX.text
    @ViewBuilder var icon: Icon
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            icon.foregroundStyle(tint).frame(width: size, height: size).background(fill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Playlists (iOS · Playlists)

struct PlaylistsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var playlists: [PlaylistSummary] = []
    @State private var laterCount = 0
    @State private var likedCount = 0
    @State private var historyCount = 0
    @State private var showNew = false
    @State private var toDelete: Playlist?
    @State private var toPublish: PlaylistSummary?
    @State private var publishing: Set<String> = []
    @State private var newTitle = ""
    @State private var sortRecent = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader("Playlists") {
                    CircleIconButtonView(label: "New playlist", fill: BX.coral, tint: BX.coralInk) { IconView(.plus, size: 20, lineWidth: 2.4) } action: { showNew = true }
                }
                HStack(spacing: 10) {
                    tile("Watch later", "\(laterCount) videos", icon: .clock, tint: BX.amber) { model.push(.watchLater) }
                    tile("Liked", "\(likedCount) videos", icon: .heart, tint: BX.coralText) { model.push(.liked) }
                    tile("History", "\(historyCount) videos", icon: .history, tint: BX.teal) { model.push(.history) }
                }
                .padding(.horizontal, 16).padding(.top, 18)

                HStack {
                    Text("Your playlists").font(.system(size: 18, weight: .bold)).kerning(-0.18).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { sortRecent.toggle() } label: {
                        HStack(spacing: 4) {
                            Text(sortRecent ? "Recent" : "A–Z").font(.system(size: 13, weight: .semibold))
                            IconView(.chevronDown, size: 14, lineWidth: 2.2)
                        }
                        .foregroundStyle(BX.text2)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(BX.surface2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sort: \(sortRecent ? "recent" : "A to Z")")
                }
                .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 14)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 22) {
                    ForEach(sorted) { p in
                        Button { model.push(.playlist(p.playlist.id)) } label: { StackedCover(summary: p) }
                            .buttonStyle(.plain)
                            .contextMenu { PlaylistActions(summary: p, publishing: publishing.contains(p.id), toDelete: $toDelete, toPublish: $toPublish) }
                            .overlay(alignment: .bottomTrailing) {
                                PlaylistMoreButton(summary: p, publishing: publishing.contains(p.id), toDelete: $toDelete, toPublish: $toPublish)
                                    .offset(x: 6, y: 2)
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .islandClearance()
        .playlistDeleteDialog($toDelete)
        .playlistPublishDialog($toPublish)
        .observing(model.store, { db in try Q.publishingPlaylists(db) }) { publishing = $0 }
        .alert("New playlist", isPresented: $showNew) {
            TextField("Name", text: $newTitle)
            Button("Create") { let t = newTitle; newTitle = ""; Task { await model.createPlaylist(title: t.isEmpty ? "New playlist" : t, music: model.mode == .music) } }
            Button("Cancel", role: .cancel) {}
        }
        .observing(model.store, { db in try Q.playlists(db) }) { playlists = $0 }
        .observing(model.store, { db in (try WatchLaterEntry.fetchCount(db), try LikedVideo.fetchCount(db), try HistoryEntry.fetchCount(db)) }) {
            laterCount = $0.0; likedCount = $0.1; historyCount = $0.2
        }
    }

    private var sorted: [PlaylistSummary] {
        sortRecent ? playlists : playlists.sorted { $0.playlist.title.localizedCaseInsensitiveCompare($1.playlist.title) == .orderedAscending }
    }

    private func tile(_ title: String, _ sub: String, icon: BXIcon, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                IconView(icon, size: 18, lineWidth: 2).foregroundStyle(tint)
                    .frame(width: 34, height: 34).background(tint.opacity(0.16), in: Circle())
                Spacer(minLength: 0)
                Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                Text(sub).font(.system(size: 12)).foregroundStyle(BX.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .frame(height: 100)
            .background(Color(hex: 0x151518), in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

struct StackedCover: View {
    var summary: PlaylistSummary
    var body: some View {
        let palette = ArtPalette.forSeed(summary.cover?.id ?? summary.playlist.id)
        VStack(alignment: .leading, spacing: 0) {
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(palette.circle.opacity(0.3)).frame(height: 5).padding(.horizontal, 16)
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(palette.circle.opacity(0.6)).frame(height: 5).padding(.horizontal, 8)
            Group {
                if let cover = summary.cover {
                    VideoThumbnail(cover, radius: 14, showDuration: false)
                } else {
                    ArtView(seed: summary.playlist.id, title: summary.playlist.title).aspectRatio(16 / 9, contentMode: .fit).clipShape(.rect(cornerRadius: 14))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 4) {
                    IconView(.list, size: 11, lineWidth: 2.6)
                    Text("\(summary.count)").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.black.opacity(0.72), in: .rect(cornerRadius: 6))
                .padding(7)
            }
            // Room on the right for the card's ⋯ button.
            Text(summary.playlist.title).font(.system(size: 14, weight: .semibold)).padding(.top, 9).lineLimit(1).padding(.trailing, 26)
            Text("\(summary.count) videos · \(summary.playlist.isPrivate ? "Private" : "Public")").font(.system(size: 12)).foregroundStyle(BX.muted).padding(.top, 2).padding(.trailing, 26)
        }
        .foregroundStyle(BX.text)
    }
}

// MARK: - You (iOS · You)

struct ProfileScreen: View {
    @Environment(AppModel.self) private var model
    @State private var stats: Q.Stats?
    @State private var history: [HistoryRow] = []
    @State private var showSettings = false
    @State private var editingName = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    ProfileAvatar(size: 80, initials: initials, photo: model.account?.pictureURL)
                        .font(BX.display(30, .bold))
                        .padding(4)
                        .overlay(Circle().strokeBorder(BX.coral, lineWidth: 2))
                        .accessibilityHidden(true)
                    Text(model.displayName).font(BX.display(25, .bold)).kerning(-0.5).padding(.top, 14)
                    Text("@\(handle) · \(stats?.subscriptions ?? 0) subscriptions").font(.system(size: 13)).foregroundStyle(BX.muted).padding(.top, 3)
                    if model.syncEnabled {
                        Label("Synced with YouTube · \(model.syncStatusText)", systemImage: model.sync.problem == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(model.sync.problem == nil ? BX.sageText : BX.amber)
                            .padding(.top, 4)
                    }
                    HStack(spacing: 8) {
                        pill("Edit profile") { editingName = true }
                        pill("Settings") { showSettings = true }
                    }
                    .padding(.top, 14)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

                if model.googleConfigured && model.account == nil {
                    Button { Task { await model.signInWithGoogle() } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 22)).foregroundStyle(BX.coralText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.isSigningIn ? "Waiting for Google…" : "Sign in with Google").font(.system(size: 15, weight: .semibold))
                                Text("Bring in your subscriptions, playlists and likes").font(.system(size: 12.5)).foregroundStyle(BX.muted)
                            }
                            Spacer()
                            if model.isSigningIn { ProgressView() } else { IconView(.chevronRight, size: 16).foregroundStyle(BX.muted) }
                        }
                        .padding(14)
                        .background(BX.surface, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BX.line))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16).padding(.top, 18)
                }

                HStack(spacing: 10) {
                    stat(Format.minutes(stats?.watchedThisWeek ?? 0), "Watched this week")
                    stat("\(stats?.playlists ?? 0)", "Playlists")
                    Button { model.push(.notes) } label: { stat("\(stats?.notes ?? 0)", "Notes") }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows all your notes")
                }
                .padding(.horizontal, 16).padding(.top, 22)

                HStack {
                    Text("History").font(.system(size: 18, weight: .bold)).kerning(-0.18).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("See all") { model.push(.history) }
                        .buttonStyle(.plain).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(BX.coralText)
                }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 12)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(history) { r in
                            Button { model.open(r.video) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    VideoThumbnail(r.video, radius: 14, showDuration: false, progress: r.entry.progress)
                                    Text(r.video.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                }
                                .frame(width: 200)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                VStack(spacing: 0) {
                    row("Watch later", icon: .clock, tint: BX.amber, first: true) { model.push(.watchLater) }
                    row("Liked videos", icon: .heart, tint: BX.coralText) { model.push(.liked) }
                    row("Notes", icon: .comment, tint: BX.amber, detail: (stats?.notes ?? 0) > 0 ? "\(stats?.notes ?? 0)" : "") { model.push(.notes) }
                    row("Calm mode", icon: .leaf, tint: BX.sageText, detail: model.calmMode ? "On" : "Off") { model.calmMode.toggle() }
                    row("Music mode", icon: .music, tint: Color(hex: 0xB3A1FF), detail: model.mode == .music ? "On" : "Off") { model.mode = model.mode == .music ? .videos : .music }
                }
                .background(Color(hex: 0x151518), in: .rect(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.06)))
                .padding(.horizontal, 16).padding(.top, 22)
            }
        }
        .overlay(alignment: .topTrailing) {
            CircleIconButtonView(label: "Settings") { IconView(.sliders, size: 19, lineWidth: 1.8) } action: { showSettings = true }
                .padding(.trailing, 16).padding(.top, 2)
        }
        .islandClearance()
        .sheet(isPresented: $showSettings) { SettingsSheet().environment(model) }
        .alert("Your name", isPresented: $editingName) {
            TextField("Name", text: Binding(get: { model.displayName }, set: { model.displayName = $0 }))
            Button("Done") {}
        }
        .observing(model.store, { db in try Q.stats(db) }) { stats = $0 }
        .observing(model.store, { db in try Q.history(db, limit: 8) }) { history = $0 }
    }

    private var initials: String {
        let letters = model.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "JD" : letters.uppercased()
    }

    private var handle: String { model.displayName.lowercased().replacingOccurrences(of: " ", with: "") }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(BX.text)
                .padding(.horizontal, 16).frame(height: 36)
                .background(Color(hex: 0x1E1E22), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(BX.display(20, .bold)).kerning(-0.4).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 11.5)).foregroundStyle(BX.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(hex: 0x151518), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }

    private func row(_ title: String, icon: BXIcon, tint: Color, detail: String = "", first: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconView(icon, size: 15, lineWidth: 2.2).foregroundStyle(tint)
                    .frame(width: 30, height: 30).background(tint.opacity(0.16), in: .rect(cornerRadius: 9))
                Text(title).font(.system(size: 14.5, weight: .medium)).foregroundStyle(BX.text)
                Spacer()
                Text(detail).font(.system(size: 13)).foregroundStyle(BX.dim)
                IconView(.chevronRight, size: 16, lineWidth: 2.2).foregroundStyle(Color(hex: 0x5A5A63))
            }
            .padding(.horizontal, 14).frame(height: 52)
            .overlay(alignment: .top) { if !first { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
