import SwiftUI
import BoxtubeCore
import BoxtubeUI

// MARK: - Home

struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var topic = Topic.all[0]
    @State private var feed: [Video] = []
    @State private var topicVideos: [Video] = []
    @State private var shorts: [Video] = []
    @State private var progress: [String: Double] = [:]
    @State private var topicError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HomeHeader().padding(.top, 6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Topic.all) { t in
                            Chip(t.title, selected: t == topic, dot: t.id == "live" ? BX.coral : nil) { withAnimation(.snappy) { topic = t } }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 14)

                if topic.id == "all" {
                    let newest = feed.first { (progress[$0.id] ?? 0) < 0.05 } ?? feed.first
                    if let featured = newest {
                        HomeCard(video: featured, label: "New from \(featured.channelTitle)", progress: progress[featured.id])
                            .padding(.horizontal, 16).padding(.top, 18)
                    }
                    if !shorts.isEmpty {
                        HStack(alignment: .center) {
                            HStack(spacing: 8) {
                                IconView(.shorts, size: 20, lineWidth: 2, fill: BX.coral).foregroundStyle(BX.coral)
                                Text("Shorts").font(.system(size: 18, weight: .bold)).kerning(-0.18)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button("See all") { model.tab = .shorts }
                                .buttonStyle(.plain)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(BX.coralText)
                        }
                        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 12)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(shorts.prefix(10)) { s in ShortCard(video: s) { model.tab = .shorts } }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    ForEach(feed.filter { $0.id != newest?.id }) { v in
                        HomeCard(video: v, progress: progress[v.id]).padding(.horizontal, 16).padding(.top, 26)
                    }
                    if feed.isEmpty {
                        HintCard(icon: model.isRefreshing ? "arrow.triangle.2.circlepath" : "rectangle.stack.badge.play",
                                 title: model.isRefreshing ? "Loading your subscriptions…" : "Nothing here yet",
                                 message: "Home is built from the channels you follow. Pull to refresh, or add channels in Subscriptions.")
                            .padding(16)
                    }
                } else {
                    if !model.hasAPIKey {
                        HintCard(icon: "key", title: "Topics need an API key", message: "Add a YouTube Data API key to apple/Config/Secrets.xcconfig to browse topics and search.")
                            .padding(16)
                    } else if let topicError {
                        HintCard(icon: "exclamationmark.triangle", title: "Couldn't load \(topic.title)", message: topicError).padding(16)
                    }
                    ForEach(topicVideos) { v in
                        HomeCard(video: v, progress: progress[v.id]).padding(.horizontal, 16).padding(.top, 22)
                    }
                }
            }
        }
        .onScrollPhaseChange { _, phase in model.preview.scrollPhase(isScrolling: phase != .idle) }
        .onDisappear { model.preview.stop() }
        .islandClearance()
        .refreshable { await model.refresh(force: true) }
        .observing(model.store, { db in try Q.feed(db) }) { feed = $0 }
        .observing(model.store, { db in try Q.shorts(db) }) { shorts = $0 }
        .observing(model.store, { db in try Q.progress(db) }) { progress = $0 }
        .observing(model.store, id: topic.id, { [key = "topic:\(topic.id)"] db in try Q.cachedList(db, key: key) }) { topicVideos = $0 }
        .task(id: topic.id) {
            topicError = nil
            guard topic.id != "all", model.hasAPIKey else { return }
            do { try await model.feed.loadTopic(topic) } catch { topicError = error.localizedDescription }
        }
    }
}

/// iOS · Home header: brand mark + wordmark, cast and bell.
struct HomeHeader: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                BrandMark(size: 30)
                Text("Boxtube").font(BX.display(23, .heavy)).kerning(-0.575)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Boxtube")
            Spacer()
            HStack(spacing: 8) {
                CastButton()
                Button { model.tab = .subs } label: {
                    IconView(.bell, size: 19, lineWidth: 1.8).foregroundStyle(BX.text)
                        .frame(width: 40, height: 40)
                        .background(BX.surface2, in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if !model.calmMode {
                                Circle().fill(BX.coral).frame(width: 8, height: 8)
                                    .overlay(Circle().strokeBorder(BX.surface2, lineWidth: 2))
                                    .offset(x: -9, y: 8)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notifications")
            }
        }
        .padding(.leading, 20).padding(.trailing, 16)
        .frame(height: 44)
    }
}

/// Feed card from iOS · Home: 22 pt thumbnail (optional glass label), 36 pt avatar, 15.5 pt title, more button.
struct HomeCard: View {
    @Environment(AppModel.self) private var model
    var video: Video
    var label: String? = nil
    var progress: Double? = nil
    @State private var playlists: [PlaylistSummary] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.open(video) } label: {
                VideoThumbnail(video, radius: 22, progress: progress, inset: 10)
                    .videoPreview(video, cornerRadius: 22)
                    .overlay(alignment: .topLeading) {
                        if let label {
                            Text(label)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .background(Color(hex: 0x0C0C10, opacity: 0.5), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.16)))
                                .padding(12)
                        }
                    }
            }
            .buttonStyle(.plain)
            HStack(alignment: .top, spacing: 12) {
                ChannelAvatar(title: video.channelTitle, size: 36)
                Button { model.open(video) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.title).font(.system(size: 15.5, weight: .semibold)).lineSpacing(1.5)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Text([video.channelTitle, Format.views(video.viewCount), Format.ago(video.publishedAt)].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12.5)).foregroundStyle(BX.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                VideoMoreButton(video: video, size: 18)
            }
            .padding(.horizontal, 4).padding(.top, 12)
        }
        .observing(model.store, { db in try Q.playlists(db) }) { playlists = $0 }
    }
}

struct ModeSwitch: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppMode.allCases) { m in
                let on = model.mode == m
                Button { withAnimation(.snappy) { model.mode = m } } label: {
                    HStack(spacing: 5) {
                        if m == .music && on { Image(systemName: "music.note").font(.system(size: 11, weight: .bold)) }
                        Text(m.title).font(.system(size: 13, weight: on ? .bold : .semibold))
                    }
                    .padding(.horizontal, 13).frame(height: 30)
                    .foregroundStyle(on ? (m == .music ? BX.coralInk : BX.ground) : BX.muted)
                    .background(on ? (m == .music ? BX.coral : BX.text) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color(hex: 0x18181B), in: Capsule())
    }
}

// MARK: - Calm (idea 03)

struct CalmHomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var feed: [Video] = []

    var body: some View {
        let today = feed.filter { Calendar.current.isDateInToday($0.publishedAt) }
        let earlier = feed.filter { !Calendar.current.isDateInToday($0.publishedAt) }.prefix(12)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    BrandMark(fill: BX.sage)
                    Text("Boxtube").font(BX.display(23)).kerning(-0.6)
                    Spacer()
                    Button { withAnimation(.smooth) { model.calmMode = false } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "leaf.fill")
                            Text("Calm").font(.system(size: 13, weight: .bold))
                            Toggle("", isOn: .constant(true)).labelsHidden().tint(BX.sage).allowsHitTesting(false).scaleEffect(0.75)
                        }
                        .foregroundStyle(BX.sageText)
                        .padding(.leading, 12).frame(height: 36)
                        .background(BX.sage.opacity(0.16), in: Capsule())
                        .overlay(Capsule().strokeBorder(BX.sage.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Calm mode on. Turn off")
                }
                .padding(.leading, 20).padding(.trailing, 16).padding(.top, 6)

                Text("Only channels you follow, newest first. No recommendations, no view counts, no Shorts. You're caught up after \(Text("\(today.count + earlier.count) videos").foregroundStyle(Color(hex: 0xECEDEA)).bold()).")
                    .font(.system(size: 14)).foregroundStyle(Color(hex: 0xA9ADA6)).lineSpacing(3)
                    .padding(.horizontal, 20).padding(.top, 16)

                if !today.isEmpty { calmSection("Today", today) }
                if !earlier.isEmpty { calmSection("Earlier", Array(earlier)) }

                Text("That's everything. Go do something nice.")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x8F948C))
                    .frame(maxWidth: .infinity).padding(.top, 30)
            }
        }
        .background(BX.calmGround)
        .islandClearance()
        .observing(model.store, { db in try Q.feed(db, limit: 30) }) { feed = $0 }
    }

    private func calmSection(_ title: String, _ videos: [Video]) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(title.uppercased()).font(.system(size: 13, weight: .semibold)).kerning(0.8).foregroundStyle(Color(hex: 0x8F948C))
                .padding(.horizontal, 4)
            ForEach(videos) { v in VideoCard(video: v, showCounts: false, muted: true) }
        }
        .padding(.horizontal, 16).padding(.top, 22)
    }
}

// MARK: - Search results

struct SearchResultsScreen: View {
    @Environment(AppModel.self) private var model
    var query: String
    @State private var results: [Video] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack { BackButton(); Text("“\(query)”").font(.system(size: 20, weight: .bold)); Spacer() }
                if let error { HintCard(icon: "key", title: "Search unavailable", message: error) }
                ForEach(results.filter { !model.isHidden($0) }) { VideoRow(video: $0) }
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .islandClearance()
        .task {
            do { results = try await model.feed.search(query) } catch { self.error = error.localizedDescription }
        }
    }
}
