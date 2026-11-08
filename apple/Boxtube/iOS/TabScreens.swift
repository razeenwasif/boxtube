import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

// MARK: - Subscriptions

struct ManageSubscriptionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var subs: [Q.SubscriptionRow] = []
    @State private var query = ""
    @State private var results: [Channel] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(model.hasAPIKey ? "Search channels, or paste a channel URL / ID" : "Paste a channel URL or ID (UC…)", text: $query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onSubmit(find)
                        Button("Add", action: find).disabled(query.isEmpty)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(BX.coralText) }
                    ForEach(results) { c in
                        HStack {
                            ChannelAvatar(title: c.title, url: c.avatarURL, size: 32)
                            Text(c.title)
                            Spacer()
                            Button("Subscribe") { model.subscribe(c); results.removeAll { $0.id == c.id } }.buttonStyle(.borderedProminent).tint(BX.coral)
                        }
                    }
                } header: { Text("Add a channel") }
                Section {
                    ForEach(subs) { row in
                        HStack {
                            ChannelAvatar(title: row.channel.title, url: row.channel.avatarURL, size: 32)
                            Text(row.channel.title)
                            Spacer()
                            if row.channel.isMusic { Image(systemName: "music.note").foregroundStyle(BX.muted) }
                        }
                    }
                    .onDelete { idx in for i in idx { model.unsubscribe(subs[i].channel.id) } }
                } header: { Text("\(subs.count) subscriptions") }
            }
            .navigationTitle("Subscriptions")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .observing(model.store, { db in try Q.subscriptions(db) }) { subs = $0 }
    }

    private func find() {
        error = nil
        let text = query.trimmingCharacters(in: .whitespaces)
        if let id = ChannelLink.channelId(from: text) {
            model.subscribe(Channel(id: id, title: id))
            query = ""
            return
        }
        guard model.hasAPIKey else { error = "That doesn't look like a channel ID. Channel IDs start with UC."; return }
        Task {
            do { results = try await model.feed.searchChannels(text) } catch { self.error = error.localizedDescription }
        }
    }
}

enum ChannelLink {
    static func channelId(from text: String) -> String? {
        if let m = text.firstMatch(of: /(UC[A-Za-z0-9_-]{22})/) { return String(m.1) }
        return nil
    }
}

// MARK: - Playlists

struct PlaylistDetailScreen: View {
    @Environment(AppModel.self) private var model
    var playlistId: String
    @State private var playlist: Playlist?
    @State private var videos: [Video] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack { BackButton(); Spacer() }
                if let playlist {
                    LargeTitle(playlist.title, size: 30)
                    Text("\(videos.count) videos · \(Format.minutes(Double(videos.compactMap(\.durationSeconds).reduce(0, +))))").font(.system(size: 13)).foregroundStyle(BX.muted)
                }
                HStack(spacing: 10) {
                    Button { model.play(list: videos, from: playlist?.title ?? "Playlist", playlistId: playlistId) } label: {
                        Label("Play all", systemImage: "play.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(BX.coralInk)
                            .frame(maxWidth: .infinity).frame(height: 46).background(BX.coral, in: Capsule())
                    }
                    Button { model.play(list: videos.shuffled(), from: playlist?.title ?? "Playlist", playlistId: playlistId) } label: {
                        Label("Shuffle", systemImage: "shuffle").font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 46).background(BX.surface3, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .disabled(videos.isEmpty)
                if let playlist {
                    Toggle(isOn: Binding(get: { playlist.isMusic }, set: { on in Task { try? await model.store.setPlaylistMusic(playlistId, on) } })) {
                        Label("Show in Music", systemImage: "music.note").font(.system(size: 15, weight: .semibold))
                    }
                    .tint(BX.coral)
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(BX.surface, in: .rect(cornerRadius: 14))
                }
                ForEach(videos) { v in
                    VideoRow(video: v)
                        .swipeActions { Button(role: .destructive) { Task { try? await model.store.remove(videoId: v.id, fromPlaylist: playlistId) } } label: { Label("Remove", systemImage: "trash") } }
                }
                if videos.isEmpty { HintCard(icon: "text.badge.plus", title: "Empty playlist", message: "Long-press any video and choose Add to playlist.") }
            }
            .padding(.horizontal, 16)
        }
        .islandClearance()
        .observing(model.store, { [playlistId] db in try Playlist.fetchOne(db, key: playlistId) }) { playlist = $0 }
        .observing(model.store, { [playlistId] db in try Q.playlistVideos(db, id: playlistId) }) { videos = $0 }
    }
}

// MARK: - Watch later (idea 02)

struct WatchLaterScreen: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [WatchLaterRow] = []

    var body: some View {
        let weeks = model.clearAfterWeeks
        let leaving = rows.filter { !$0.entry.pinned && $0.expiresAt(clearAfter: weeks) < .now.addingTimeInterval(7 * 86_400) }
        let total = rows.compactMap(\.video.durationSeconds).reduce(0, +)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    BackButton()
                    Spacer()
                    Menu {
                        Picker("Clear after", selection: Binding(get: { model.clearAfterWeeks }, set: { model.clearAfterWeeks = $0 })) {
                            ForEach([1, 2, 4, 8], id: \.self) { Text("\($0) week\($0 == 1 ? "" : "s")").tag($0) }
                        }
                    } label: {
                        Label("Clears after \(weeks) weeks", systemImage: "clock").font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 12).frame(height: 34).background(BX.surface2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                LargeTitle("Watch later").padding(.horizontal, 20).padding(.top, 6)
                Text(rows.isEmpty ? "Nothing piles up here" : "\(rows.count) video\(rows.count == 1 ? "" : "s") · \(Format.minutes(Double(total))) · nothing piles up").font(.system(size: 13)).foregroundStyle(BX.muted).padding(.horizontal, 20).padding(.top, 4)

                if !leaving.isEmpty {
                    HStack(spacing: 14) {
                        ZStack(alignment: .bottomLeading) {
                            ForEach(Array(leaving.prefix(3).enumerated().reversed()), id: \.element.id) { i, r in
                                VideoThumbnail(r.video, radius: 7, showDuration: false).frame(width: 64)
                                    .opacity(1 - Double(i) * 0.3)
                                    .offset(x: CGFloat(i) * 8, y: -CGFloat(i) * 11)
                            }
                        }
                        .frame(width: 84, height: 60, alignment: .bottomLeading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LAST CALL").font(.system(size: 11, weight: .heavy)).kerning(0.9).foregroundStyle(BX.coralText)
                            Text("\(leaving.count) video\(leaving.count == 1 ? "" : "s") leave\(leaving.count == 1 ? "s" : "") \(leavePhrase(leaving.map { $0.expiresAt(clearAfter: weeks) }.min()))")
                                .font(.system(size: 14.5, weight: .bold))
                            HStack(spacing: 8) {
                                Button("Play them now") { model.play(segments: leaving.map { QueueSegment(video: $0.video, start: 0, end: nil) }) }
                                    .font(.system(size: 12.5, weight: .bold)).foregroundStyle(BX.coralInk).padding(.horizontal, 12).frame(height: 30).background(BX.coral, in: Capsule())
                                Button("Keep all") { Task { try? await model.store.keepWatchLater(leaving.map(\.video.id)) } }
                                    .font(.system(size: 12.5, weight: .semibold)).padding(.horizontal, 12).frame(height: 30).background(BX.surface3, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 7)
                        }
                    }
                    .padding(14)
                    .background(BX.coral.opacity(0.08), in: .rect(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(BX.coral.opacity(0.35)))
                    .padding(.horizontal, 16).padding(.top, 18)
                }

                VStack(spacing: 14) {
                    ForEach(rows) { r in
                        let life = r.life(clearAfter: weeks)
                        let soon = !r.entry.pinned && life < 0.2
                        Button { model.open(r.video) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 5) {
                                    VideoThumbnail(r.video, radius: 11)
                                    ProgressLine(value: life, height: 3, tint: r.entry.pinned ? BX.amber : (soon ? BX.coral : Color(hex: 0x6E6E78)), track: BX.surface3).clipShape(Capsule())
                                }
                                .frame(width: 140)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(r.video.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(r.video.channelTitle).font(.system(size: 12)).foregroundStyle(BX.muted)
                                    Text(status(r, weeks: weeks)).font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(r.entry.pinned ? BX.amber : (soon ? BX.coralText : BX.muted))
                                }
                                Spacer(minLength: 0)
                            }
                            .opacity(r.entry.pinned ? 1 : 0.5 + life / 2)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { Task { try? await model.store.setPinned(r.video.id, pinned: !r.entry.pinned) } } label: { Label(r.entry.pinned ? "Unpin" : "Pin (never clears)", systemImage: "pin") }
                            Button(role: .destructive) { model.toggleWatchLater(r.video.id) } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 20)
                if rows.isEmpty { HintCard(icon: "clock", title: "Nothing saved", message: "Save videos to watch later. Anything you don't get to clears itself after \(weeks) weeks.").padding(16) }
            }
        }
        .islandClearance()
        .observing(model.store, { db in try Q.watchLater(db) }) { rows = $0 }
    }

    private func leavePhrase(_ date: Date?) -> String {
        guard let date else { return "soon" }
        let days = date.timeIntervalSinceNow / 86_400
        if days < 1 { return "tomorrow" }
        return "on " + date.formatted(.dateTime.weekday(.wide))
    }

    private func status(_ r: WatchLaterRow, weeks: Int) -> String {
        if r.entry.pinned { return "Pinned · stays" }
        let left = r.expiresAt(clearAfter: weeks).timeIntervalSinceNow
        if left < 86_400 { return "Leaves tomorrow" }
        if left < 7 * 86_400 { return "Leaves in \(Int(left / 86_400)) days" }
        return "Saved \(Format.ago(r.entry.savedAt))"
    }
}

// MARK: - Simple lists

struct VideoListScreen: View {
    enum Kind { case liked, history }
    @Environment(AppModel.self) private var model
    var title: String
    var kind: Kind
    @State private var videos: [Video] = []
    @State private var progress: [String: Double] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack {
                    BackButton(); Spacer()
                    if kind == .history, !videos.isEmpty {
                        Button("Clear") { Task { try? await model.store.clearHistory() } }.font(.system(size: 14, weight: .semibold)).foregroundStyle(BX.coralText)
                    }
                }
                LargeTitle(title)
                ForEach(videos) { VideoRow(video: $0, progress: progress[$0.id]) }
                if videos.isEmpty { HintCard(icon: kind == .liked ? "heart" : "clock.arrow.circlepath", title: "Nothing yet", message: kind == .liked ? "Videos you like show up here." : "Videos you watch show up here.") }
            }
            .padding(.horizontal, 16)
        }
        .islandClearance()
        .observing(model.store, { [kind] db in kind == .liked ? try Q.liked(db) : try Q.history(db, limit: 100).map(\.video) }) { videos = $0 }
        .observing(model.store, { db in try Q.progress(db) }) { progress = $0 }
    }
}

struct ChannelScreen: View {
    @Environment(AppModel.self) private var model
    var channelId: String
    @State private var channel: Channel?
    @State private var videos: [Video] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack { BackButton(); Spacer() }
                HStack(spacing: 14) {
                    ChannelAvatar(title: channel?.title ?? "", url: channel?.avatarURL, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(channel?.title ?? "Channel").font(BX.display(24, .bold))
                        if let subs = Format.count(channel?.subscriberCount) { Text("\(subs) subscribers").font(.system(size: 13)).foregroundStyle(BX.muted) }
                    }
                    Spacer()
                }
                if let channel {
                    Button { channel.isSubscribed ? model.unsubscribe(channel.id) : model.subscribe(channel) } label: {
                        Text(channel.isSubscribed ? "Subscribed" : "Subscribe").font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .foregroundStyle(channel.isSubscribed ? BX.text : BX.ground)
                            .background(channel.isSubscribed ? BX.surface3 : BX.text, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(videos) { VideoRow(video: $0) }
            }
            .padding(.horizontal, 16)
        }
        .islandClearance()
        .observing(model.store, { [channelId] db in try Channel.fetchOne(db, key: channelId) }) { channel = $0 }
        .observing(model.store, { [channelId] db in try Q.channelVideos(db, channelId: channelId) }) { videos = $0 }
        .task {
            if let result = try? await RSSFeed.fetch(channelId: channelId) {
                try? await model.store.upsert(channels: [result.channel])
                try? await model.store.upsert(videos: result.videos)
            }
        }
    }
}

// MARK: - You

struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Watching") {
                    Toggle("Calm mode", isOn: $model.calmMode)
                    Picker("Watch later clears after", selection: $model.clearAfterWeeks) {
                        ForEach([1, 2, 4, 8], id: \.self) { Text("\($0) week\($0 == 1 ? "" : "s")").tag($0) }
                    }
                    Toggle("Tint from the video", isOn: $model.tintFromVideo)
                }
                Section {
                    GoogleAccountSection()
                } header: { Text("YouTube account") } footer: {
                    Text("Read-only: Boxtube copies your subscriptions, playlists and liked videos. Changes you make here stay in Boxtube.")
                }
                Section {
                    LabeledContent("YouTube API key", value: model.hasAPIKey ? "Added" : "Missing")
                } header: { Text("Data") } footer: {
                    Text(model.hasAPIKey ? "Search, topics and video lengths are on." : "Subscriptions work without a key. Add one in apple/Config/Secrets.xcconfig for search, topics and video lengths.")
                }
                Section {
                    Button("Clear watch history", role: .destructive) { Task { try? await model.store.clearHistory() } }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
