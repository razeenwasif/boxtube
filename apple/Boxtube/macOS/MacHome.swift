import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

/// Mac home page, laid out to match the "macOS · Home" artboard.
struct MacHome: View {
    @Environment(AppModel.self) private var model
    @State private var topic = Topic.all[0]
    @State private var feed: [Video] = []
    @State private var topicVideos: [Video] = []
    @State private var resume: [HistoryRow] = []
    @State private var fresh: [Video] = []
    @State private var progress: [String: Double] = [:]
    @State private var topicError: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .top), count: 4)

    var body: some View {
        let heroItem = resume.first
        let heroVideo = heroItem?.video ?? feed.first
        let freshList = Array((fresh.isEmpty ? feed.dropFirst() : fresh[...]).filter { $0.id != heroVideo?.id }.prefix(3))
        let shown = Set([heroVideo?.id].compactMap { $0} + freshList.map(\.id))
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(greeting), \(firstName)").font(BX.display(32, .bold)).kerning(-0.8)
                        .accessibilityAddTraits(.isHeader)
                    Text("Pick up where you left off, or catch up on what's new.")
                        .font(.system(size: 14)).foregroundStyle(BX.muted)
                }

                HStack(alignment: .top, spacing: 20) {
                    Group {
                        if let heroVideo { HeroCard(video: heroVideo, history: heroItem) } else { HeroPlaceholder() }
                    }
                    .frame(maxWidth: .infinity)
                    FreshCard(videos: freshList, newCount: fresh.count)
                        .frame(width: 360)
                }
                .frame(height: 316)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Topic.all) { t in
                            Button { withAnimation(.snappy) { topic = t } } label: {
                                Text(t.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 14).frame(height: 32)
                                    .foregroundStyle(t == topic ? BX.ground : BX.text2)
                                    .background(t == topic ? BX.text : Color(hex: 0x17171A), in: Capsule())
                                    .overlay(Capsule().strokeBorder(t == topic ? .clear : BX.line))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(t == topic ? .isSelected : [])
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(topic.id == "all" ? "Recommended for you" : topic.title)
                            .font(.system(size: 18, weight: .bold)).kerning(-0.2)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Refresh") {
                            Task {
                                if topic.id == "all" { await model.refresh(force: true) }
                                else { try? await model.feed.loadTopic(topic, maxAge: 0) }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BX.coralText)
                    }
                    if topic.id != "all", !model.hasAPIKey {
                        HintCard(icon: "key", title: "Topics need an API key", message: "Add a YouTube Data API key in apple/Config/Secrets.xcconfig to browse topics and search.")
                    } else if topic.id != "all", let topicError {
                        HintCard(icon: "exclamationmark.triangle", title: "Couldn't load \(topic.title)", message: topicError)
                    }
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(topic.id == "all" ? recommended(excluding: shown) : topicVideos) { v in
                            MacVideoCard(video: v, progress: progress[v.id])
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .observing(model.store, { db in try Q.feed(db, limit: 80) }) { feed = $0 }
        .observing(model.store, { db in try Q.history(db, limit: 2, unfinishedOnly: true) }) { resume = $0 }
        .observing(model.store, { db in
            let channels = try Channel.filter(Column("isSubscribed") == true).fetchAll(db)
            let seen = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0.lastSeenAt ?? $0.subscribedAt ?? .distantPast) })
            return try Q.feed(db, limit: 40).filter { $0.publishedAt > (seen[$0.channelId] ?? .distantPast) }
        }) { fresh = $0 }
        .observing(model.store, { db in try Q.progress(db) }) { progress = $0 }
        .observing(model.store, id: topic.id, { [key = "topic:\(topic.id)"] db in try Q.cachedList(db, key: key) }) { topicVideos = $0 }
        .task(id: topic.id) {
            topicError = nil
            guard topic.id != "all", model.hasAPIKey else { return }
            do { try await model.feed.loadTopic(topic) } catch { topicError = error.localizedDescription }
        }
    }

    /// Unwatched videos first, newest first; partly watched next; finished last.
    private func recommended(excluding shown: Set<String>) -> [Video] {
        feed.filter { !shown.contains($0.id) }
            .sorted { a, b in
                let pa = progress[a.id] ?? 0, pb = progress[b.id] ?? 0
                let ra = pa < 0.05 ? 0 : (pa < 0.95 ? 1 : 2), rb = pb < 0.05 ? 0 : (pb < 0.95 ? 1 : 2)
                return ra != rb ? ra < rb : a.publishedAt > b.publishedAt
            }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        return h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
    }

    private var firstName: String { model.displayName.split(separator: " ").first.map(String.init) ?? model.displayName }
}

// MARK: - Hero

private struct HeroCard: View {
    @Environment(AppModel.self) private var model
    var video: Video
    var history: HistoryRow?
    @State private var playlists: [PlaylistSummary] = []

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button { model.open(video) } label: {
                ZStack {
                    Color.clear.overlay { HeroImage(video: video) }
                        .overlay { PreviewLayer(video: video, showBadge: false) }
                        .clipped()
                    LinearGradient(stops: [
                        .init(color: Color(hex: 0x080A10, opacity: 0.92), location: 0),
                        .init(color: Color(hex: 0x080A10, opacity: 0.55), location: 0.4),
                        .init(color: Color(hex: 0x080A10, opacity: 0), location: 0.7),
                    ], startPoint: .bottom, endPoint: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
                .contentShape(.rect(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .previewTrigger(video)
            .accessibilityLabel("\(history == nil ? "Play" : "Resume") \(video.title)")

            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(history == nil ? "NEW FROM \(video.channelTitle.uppercased())" : "CONTINUE WATCHING")
                        .font(.system(size: 11.5, weight: .bold)).kerning(0.9).foregroundStyle(BX.coralText)
                    Text(video.title).font(BX.display(28, .bold)).kerning(-0.5).lineLimit(2)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Color(hex: 0xC7C7CC)).lineLimit(1)
                    if let history {
                        ProgressLine(value: history.entry.progress, height: 4, track: .white.opacity(0.2))
                            .clipShape(Capsule())
                            .frame(maxWidth: 420)
                            .padding(.top, 8)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Button { model.open(video) } label: {
                        Label(history.map { "Resume · \(Format.minutes($0.entry.remainingSeconds)) left" } ?? "Play", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(BX.coralInk)
                            .padding(.horizontal, 18).frame(height: 40)
                            .background(BX.coral, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Menu {
                        Button(model.watchLaterIds.contains(video.id) ? "Remove from Watch later" : "Save to Watch later") { model.toggleWatchLater(video.id) }
                        if !playlists.isEmpty { Divider() }
                        ForEach(playlists) { p in Button("Add to \(p.playlist.title)") { model.add(video.id, to: p.playlist) } }
                    } label: {
                        Image(systemName: "text.badge.plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .boxGlass(Circle(), tint: .white.opacity(0.08))
                    }
                    .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
                    .help("Save to playlist")
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 24)
        }
        .observing(model.store, { db in try Q.playlists(db) }) { playlists = $0 }
    }

    private var subtitle: String {
        if let history, let c = Chapter.current(in: video.chapters, at: history.entry.positionSeconds) {
            return "\(video.channelTitle) · Chapter \(c.index + 1) of \(video.chapters.count), \(c.title)"
        }
        if let history { return "\(video.channelTitle) · \(Format.clock(history.entry.positionSeconds)) of \(Format.clock(history.entry.durationSeconds))" }
        return [video.channelTitle, Format.views(video.viewCount), Format.ago(video.publishedAt)].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct HeroPlaceholder: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BX.surface)
            .overlay {
                VStack(spacing: 8) {
                    if model.isRefreshing { ProgressView() }
                    Text(model.isRefreshing ? "Loading your subscriptions…" : "Subscribe to a few channels to fill your home page.")
                        .font(.system(size: 13)).foregroundStyle(BX.muted)
                }
            }
    }
}

// MARK: - New from subscriptions

private struct FreshCard: View {
    @Environment(AppModel.self) private var model
    var videos: [Video]
    var newCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("New from subscriptions").font(.system(size: 15, weight: .bold))
                Spacer()
                if newCount > 0 {
                    Text("\(newCount) new").font(.system(size: 11.5, weight: .bold)).foregroundStyle(BX.coralInk)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(BX.coral, in: Capsule())
                }
            }
            ForEach(videos) { v in
                HStack(alignment: .top, spacing: 0) {
                    Button { model.open(v) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VideoThumbnail(v, radius: 10).frame(width: 128)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(v.title).font(.system(size: 13, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                Text("\(v.channelTitle) · \(Format.ago(v.publishedAt))").font(.system(size: 12)).foregroundStyle(BX.muted).lineLimit(1)
                            }
                            .padding(.top, 1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    VideoMoreButton(video: v, size: 14).padding(.top, -6).padding(.trailing, -8)
                }
                .videoContextMenu(v)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(hex: 0x141417), in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }
}

// MARK: - Grid card

struct MacVideoCard: View {
    @Environment(AppModel.self) private var model
    var video: Video
    var progress: Double?
    @State private var channel: Channel?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { model.open(video) } label: {
                VideoThumbnail(video, radius: 14, progress: progress)
                    .videoPreview(video, cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(video.title), \(video.channelTitle)")
            HStack(alignment: .top, spacing: 4) {
                Button { model.open(video) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        ChannelAvatar(title: video.channelTitle, url: channel?.avatarURL, size: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(video.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineSpacing(1.5)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(video.channelTitle).font(.system(size: 12.5)).foregroundStyle(BX.muted)
                            Text([Format.views(video.viewCount), Format.ago(video.publishedAt)].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 12.5)).foregroundStyle(BX.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
                VideoMoreButton(video: video).padding(.top, -6)
            }
        }
        .videoContextMenu(video)
        .observing(model.store, id: video.channelId, { [id = video.channelId] db in try Channel.fetchOne(db, key: id) }) { channel = $0 }
    }
}

// MARK: - Explore (topics)

struct MacExplore: View {
    @Environment(AppModel.self) private var model
    @State private var topic = Topic.all[1]
    @State private var videos: [Video] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LargeTitle("Explore")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Topic.all.dropFirst()) { t in Chip(t.title, selected: t == topic) { topic = t } }
                    }
                }
                if !model.hasAPIKey {
                    HintCard(icon: "key", title: "Explore needs an API key", message: "Add a YouTube Data API key in apple/Config/Secrets.xcconfig to browse topics beyond your subscriptions.")
                } else if let error {
                    HintCard(icon: "exclamationmark.triangle", title: "Couldn't load \(topic.title)", message: error)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .top), count: 4), spacing: 28) {
                    ForEach(videos) { MacVideoCard(video: $0) }
                }
            }
            .padding(28)
        }
        .observing(model.store, id: topic.id, { [key = "topic:\(topic.id)"] db in try Q.cachedList(db, key: key) }) { videos = $0 }
        .task(id: topic.id) {
            error = nil
            guard model.hasAPIKey else { return }
            do { try await model.feed.loadTopic(topic) } catch { self.error = error.localizedDescription }
        }
    }
}
