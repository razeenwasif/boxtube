import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

private let gridColumns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 20, alignment: .top)]

struct MacCalmHome: View {
    @Environment(AppModel.self) private var model
    @State private var feed: [Video] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label("Calm mode", systemImage: "leaf.fill").font(BX.display(28, .bold)).foregroundStyle(BX.sageText)
                    Spacer()
                    Button("Turn off") { model.calmMode = false }.buttonStyle(.bordered)
                }
                Text("Only channels you follow, newest first. No recommendations, no counts, no Shorts. You're caught up after \(feed.count) videos.")
                    .font(.system(size: 14)).foregroundStyle(Color(hex: 0xA9ADA6))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 24)], spacing: 30) {
                    ForEach(feed) { VideoCard(video: $0, showCounts: false, muted: true) }
                }
            }
            .padding(28)
        }
        .observing(model.store, { db in try Q.feed(db, limit: 24) }) { feed = $0 }
    }
}

// MARK: - Lists

struct MacVideoGrid: View {
    @Environment(AppModel.self) private var model
    var title: String
    var playlistId: String? = nil
    var fetch: @Sendable (Database) throws -> [Video]
    @State private var videos: [Video] = []
    @State private var progress: [String: Double] = [:]
    @State private var name: String?
    @State private var playlist: Playlist?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    LargeTitle(name ?? title)
                    Spacer()
                    if let playlist {
                        Toggle("Show in Music", isOn: Binding(get: { playlist.isMusic }, set: { on in Task { try? await model.store.setPlaylistMusic(playlist.id, on) } }))
                            .toggleStyle(.switch).controlSize(.small).tint(BX.coral)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(BX.text2)
                            .padding(.trailing, 8)
                    }
                    if !videos.isEmpty {
                        Button { model.play(list: videos, from: name ?? title, playlistId: playlistId) } label: {
                            Label("Play all", systemImage: "play.fill").font(.system(size: 13.5, weight: .bold)).foregroundStyle(BX.coralInk)
                                .padding(.horizontal, 16).frame(height: 34).background(BX.coral, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if videos.isEmpty { HintCard(icon: "tray", title: "Nothing here yet", message: "Videos you add show up here.") }
                LazyVGrid(columns: gridColumns, spacing: 28) {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { i, v in
                        VideoCard(video: v, progress: progress[v.id]) { model.play(list: videos, from: name ?? title, playlistId: playlistId, startingAt: i) }
                    }
                }
            }
            .padding(28)
        }
        .observing(model.store, id: title + (playlistId ?? ""), fetch) { videos = $0 }
        .observing(model.store, { db in try Q.progress(db) }) { progress = $0 }
        .observing(model.store, id: playlistId ?? "", { [playlistId] db in try playlistId.flatMap { try Playlist.fetchOne(db, key: $0) } }) { playlist = $0; name = $0?.title }
    }
}

struct MacShorts: View {
    @Environment(AppModel.self) private var model
    @State private var shorts: [Video] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LargeTitle("Shorts")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 20) {
                    ForEach(shorts) { s in ShortCard(video: s, width: 190) { model.open(s) } }
                }
            }
            .padding(28)
        }
        .observing(model.store, { db in try Q.shorts(db, limit: 60) }) { shorts = $0 }
    }
}

struct MacSubscriptions: View {
    @Environment(AppModel.self) private var model
    @State private var subs: [Q.SubscriptionRow] = []
    @State private var feed: [Video] = []
    @State private var progress: [String: Double] = [:]
    @State private var adding = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    LargeTitle("Subscriptions")
                    Spacer()
                    TextField(model.hasAPIKey ? "Add a channel (name, URL or ID)" : "Add a channel by URL or ID (UC…)", text: $adding)
                        .textFieldStyle(.roundedBorder).frame(width: 320)
                        .onSubmit(add)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(subs) { row in
                            Button { model.push(.channel(row.channel.id)) } label: {
                                VStack(spacing: 7) {
                                    ChannelAvatar(title: row.channel.title, url: row.channel.avatarURL, size: 56).padding(3)
                                        .overlay(Circle().strokeBorder(row.isLive ? BX.coral : (row.newCount > 0 ? .white.opacity(0.25) : .clear), lineWidth: 2))
                                    Text(row.channel.title).font(.system(size: 11.5)).lineLimit(1).frame(width: 72)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Unsubscribe", role: .destructive) { model.unsubscribe(row.channel.id) } }
                        }
                    }
                }
                LazyVGrid(columns: gridColumns, spacing: 28) {
                    ForEach(feed) { VideoCard(video: $0, progress: progress[$0.id]) }
                }
            }
            .padding(28)
        }
        .observing(model.store, { db in try Q.subscriptions(db) }) { subs = $0 }
        .observing(model.store, { db in try Q.feed(db, limit: 120) }) { feed = $0 }
        .observing(model.store, { db in try Q.progress(db) }) { progress = $0 }
        .onDisappear { Task { try? await model.store.markChannelsSeen() } }
    }

    private func add() {
        let text = adding.trimmingCharacters(in: .whitespaces)
        adding = ""
        if let m = text.firstMatch(of: /(UC[A-Za-z0-9_-]{22})/) {
            model.subscribe(Channel(id: String(m.1), title: String(m.1)))
        } else if model.hasAPIKey {
            Task { if let c = try? await model.feed.searchChannels(text).first { model.subscribe(c) } }
        } else {
            model.flash("Paste a channel URL or ID starting with UC")
        }
    }
}

struct MacPlaylists: View {
    @Environment(AppModel.self) private var model
    @State private var playlists: [PlaylistSummary] = []
    @State private var newTitle = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    LargeTitle("Playlists")
                    Spacer()
                    TextField("New playlist", text: $newTitle).textFieldStyle(.roundedBorder).frame(width: 220)
                        .onSubmit { let t = newTitle; newTitle = ""; guard !t.isEmpty else { return }; Task { try? await model.store.createPlaylist(title: t) } }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 20)], spacing: 26) {
                    ForEach(playlists) { p in
                        Button { model.push(.playlist(p.id)) } label: { StackedCoverMac(summary: p) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(p.playlist.isMusic ? "Remove from Music" : "Show in Music") { Task { try? await model.store.setPlaylistMusic(p.id, !p.playlist.isMusic) } }
                                Button("Delete", role: .destructive) { Task { try? await model.store.deletePlaylist(p.id) } }
                            }
                    }
                }
            }
            .padding(28)
        }
        .observing(model.store, { db in try Q.playlists(db) }) { playlists = $0 }
    }
}

struct StackedCoverMac: View {
    var summary: PlaylistSummary
    var body: some View {
        let palette = ArtPalette.forSeed(summary.cover?.id ?? summary.playlist.id)
        VStack(alignment: .leading, spacing: 0) {
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(palette.circle.opacity(0.3)).frame(height: 6).padding(.horizontal, 18)
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(palette.circle.opacity(0.6)).frame(height: 6).padding(.horizontal, 9)
            Group {
                if let cover = summary.cover { VideoThumbnail(cover, radius: 14, showDuration: false) }
                else { ArtView(seed: summary.playlist.id, title: summary.playlist.title).aspectRatio(16 / 9, contentMode: .fit).clipShape(.rect(cornerRadius: 14)) }
            }
            Text(summary.playlist.title).font(.system(size: 14, weight: .semibold)).padding(.top, 9)
            Text("\(summary.count) videos").font(.system(size: 12)).foregroundStyle(BX.muted)
        }
    }
}

struct MacWatchLater: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [WatchLaterRow] = []
    var body: some View {
        let weeks = model.clearAfterWeeks
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    LargeTitle("Watch later")
                    Text("\(rows.count) videos · clears after \(weeks) weeks unless pinned").foregroundStyle(BX.muted)
                    Spacer()
                    Picker("Clear after", selection: Binding(get: { model.clearAfterWeeks }, set: { model.clearAfterWeeks = $0 })) {
                        ForEach([1, 2, 4, 8], id: \.self) { Text("\($0) week\($0 == 1 ? "" : "s")").tag($0) }
                    }
                    .frame(width: 180)
                }
                LazyVGrid(columns: gridColumns, spacing: 28) {
                    ForEach(rows) { r in
                        let life = r.life(clearAfter: weeks)
                        VStack(alignment: .leading, spacing: 6) {
                            VideoCard(video: r.video)
                            HStack {
                                ProgressLine(value: life, height: 3, tint: r.entry.pinned ? BX.amber : (life < 0.2 ? BX.coral : Color(hex: 0x6E6E78)), track: BX.surface3).clipShape(Capsule())
                                Button { Task { try? await model.store.setPinned(r.video.id, pinned: !r.entry.pinned) } } label: {
                                    Image(systemName: r.entry.pinned ? "pin.fill" : "pin").foregroundStyle(r.entry.pinned ? BX.amber : BX.muted)
                                }
                                .buttonStyle(.plain)
                                .help(r.entry.pinned ? "Pinned: never clears" : "Pin so it never clears")
                            }
                        }
                        .opacity(r.entry.pinned ? 1 : 0.5 + life / 2)
                    }
                }
            }
            .padding(28)
        }
        .observing(model.store, { db in try Q.watchLater(db) }) { rows = $0 }
    }
}

struct MacAllNotes: View {
    @Environment(AppModel.self) private var model
    @State private var groups: [(Video, [Note])] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LargeTitle("Notes")
                if groups.isEmpty { HintCard(icon: "note.text", title: "No notes yet", message: "While watching, press N to pin a note to the current moment.") }
                ForEach(groups, id: \.0.id) { video, notes in
                    VStack(alignment: .leading, spacing: 10) {
                        Button { model.open(video) } label: {
                            HStack { VideoThumbnail(video, radius: 8, showDuration: false).frame(width: 96); Text(video.title).font(.system(size: 15, weight: .bold)) }
                        }
                        .buttonStyle(.plain)
                        ForEach(notes) { n in
                            HStack(alignment: .top, spacing: 10) {
                                Button { model.open(video, at: n.time) } label: {
                                    Text(Format.clock(n.time)).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(BX.amber)
                                        .padding(.horizontal, 7).frame(height: 22).background(BX.amber.opacity(0.14), in: .rect(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                Text(n.text).textSelection(.enabled)
                            }
                        }
                    }
                    .padding(16).boxCard(16)
                }
            }
            .padding(28)
        }
        .observing(model.store, { db in
            let notes = try Note.order(Column("createdAt").desc).fetchAll(db)
            let byVideo = Dictionary(grouping: notes, by: \.videoId)
            return try byVideo.compactMap { id, n in try Video.fetchOne(db, key: id).map { ($0, n.sorted { $0.time < $1.time }) } }
                .sorted { ($0.1.first?.createdAt ?? .distantPast) > ($1.1.first?.createdAt ?? .distantPast) }
        }) { groups = $0 }
    }
}

struct MacChannel: View {
    @Environment(AppModel.self) private var model
    var channelId: String
    @State private var channel: Channel?
    @State private var videos: [Video] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    ChannelAvatar(title: channel?.title ?? "", url: channel?.avatarURL, size: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(channel?.title ?? "Channel").font(BX.display(30, .bold))
                        if let s = Format.count(channel?.subscriberCount) { Text("\(s) subscribers").foregroundStyle(BX.muted) }
                    }
                    Spacer()
                    if let channel {
                        if channel.isSubscribed {
                            Toggle("Show in Music", isOn: Binding(get: { channel.isMusic }, set: { on in Task { try? await model.store.setChannelMusic(channel.id, on) } }))
                                .toggleStyle(.switch).controlSize(.small).tint(BX.coral)
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(BX.text2)
                                .padding(.trailing, 8)
                                .help("Music channels appear under Artists in Music mode instead of the Videos feed")
                        }
                        Button(channel.isSubscribed ? "Subscribed" : "Subscribe") { channel.isSubscribed ? model.unsubscribe(channel.id) : model.subscribe(channel) }
                            .buttonStyle(.borderedProminent).tint(channel.isSubscribed ? BX.surface3 : BX.coral)
                    }
                }
                LazyVGrid(columns: gridColumns, spacing: 28) { ForEach(videos) { VideoCard(video: $0) } }
            }
            .padding(28)
        }
        .observing(model.store, id: channelId, { [channelId] db in try Channel.fetchOne(db, key: channelId) }) { channel = $0 }
        .observing(model.store, id: channelId, { [channelId] db in try Q.channelVideos(db, channelId: channelId) }) { videos = $0 }
        .task(id: channelId) {
            if let r = try? await RSSFeed.fetch(channelId: channelId) {
                try? await model.store.upsert(channels: [r.channel]); try? await model.store.upsert(videos: r.videos)
            }
        }
    }
}

struct MacSearch: View {
    @Environment(AppModel.self) private var model
    var query: String
    @State private var results: [Video] = []
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LargeTitle("“\(query)”")
                if let error { HintCard(icon: "key", title: "Search unavailable", message: error) }
                LazyVGrid(columns: gridColumns, spacing: 28) { ForEach(results) { VideoCard(video: $0) } }
            }
            .padding(28)
        }
        .task(id: query) {
            do { results = try await model.feed.search(query) } catch { self.error = error.localizedDescription }
        }
    }
}
