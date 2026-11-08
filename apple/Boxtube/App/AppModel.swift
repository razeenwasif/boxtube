import SwiftUI
import BoxtubeCore
import BoxtubePlayer
import BoxtubeUI

enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case videos, music
    var id: String { rawValue }
    var title: String { self == .videos ? "Videos" : "Music" }
}

enum Tab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home, shorts, subs, playlists, you
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"
        case .shorts: "Shorts"
        case .subs: "Subs"
        case .playlists: "Playlists"
        case .you: "You"
        }
    }
    var icon: String {
        switch self {
        case .home: "house"
        case .shorts: "play.rectangle.on.rectangle"
        case .subs: "rectangle.stack.badge.play"
        case .playlists: "music.note.list"
        case .you: "person.crop.circle"
        }
    }
}

enum Route: Hashable {
    case channel(String)
    case playlist(String)
    case watchLater
    case liked
    case history
    case search(String)
    case musicLibrary
}

/// A playable segment from a time box (start/end inside a video).
struct QueueSegment: Hashable, Sendable {
    var video: Video
    var start: Double
    var end: Double?
}

@MainActor
@Observable
final class AppModel {
    let store: Store
    let feed: FeedService
    let player: PlayerEngine
    let hasAPIKey: Bool

    // Settings
    var calmMode: Bool { didSet { defaults.set(calmMode, forKey: "calmMode") } }
    var mode: AppMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    var clearAfterWeeks: Int { didSet { defaults.set(clearAfterWeeks, forKey: "clearAfterWeeks") } }
    var tintFromVideo: Bool { didSet { defaults.set(tintFromVideo, forKey: "tintFromVideo") } }
    var displayName: String { didSet { defaults.set(displayName, forKey: "displayName") } }
    var autoplay: Bool { didSet { defaults.set(autoplay, forKey: "autoplay") } }

    // Navigation
    var tab: Tab = .home
    var paths: [Tab: [Route]] = [:]
    var watching: Video?          // iPhone full-screen watch view / Mac watch detail
    var showMusicPlayer = false
    var showTimeBox = false
    var showCommandPanel = false
    var showSkim = false
    var showChapterRing = false
    var showNotes = false
    var toast: String?
    var isRefreshing = false
    var lastError: String?
    var recentSearches: [String] { didSet { defaults.set(recentSearches, forKey: "recentSearches") } }

    // Library state mirrored for quick checks
    var likedIds: Set<String> = []
    var watchLaterIds: Set<String> = []
    var palette: VideoPalette = .standard

    // Time box queue
    var segments: [QueueSegment] = []
    /// The list the current video was started from (a playlist, Watch later…), shown as "Playing from".
    var playingFrom: PlayingFrom?
    struct PlayingFrom: Equatable {
        var title: String
        var playlistId: String?
        var videos: [Video]
        func position(of id: String?) -> Int? { videos.firstIndex { $0.id == id }.map { $0 + 1 } }
    }
    var activeSegmentEnd: Double?

    // Hooks set by platform code
    var onPlaybackChanged: ((Video?, PlayerEngine.State) -> Void)?

    private let defaults = UserDefaults.standard
    private var observers: [Task<Void, Never>] = []

    init() {
        BoxtubeFonts.register()
        let key = Bundle.main.object(forInfoDictionaryKey: "YouTubeAPIKey") as? String
        let store = (try? Store.live()) ?? (try! Store.inMemory())
        let client = YouTubeClient(apiKey: key)
        self.store = store
        self.feed = FeedService(store: store, client: client)
        self.hasAPIKey = client.hasKey
        self.player = PlayerEngine()
        calmMode = defaults.bool(forKey: "calmMode")
        mode = AppMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .videos
        clearAfterWeeks = defaults.object(forKey: "clearAfterWeeks") as? Int ?? 4
        tintFromVideo = defaults.object(forKey: "tintFromVideo") as? Bool ?? true
        displayName = defaults.string(forKey: "displayName") ?? "Jordan Diaz"
        autoplay = defaults.object(forKey: "autoplay") as? Bool ?? true
        recentSearches = defaults.stringArray(forKey: "recentSearches") ?? []

        player.onProgress = { [weak self] video, state in
            guard let self else { return }
            Task { try? await self.store.recordProgress(videoId: video.id, position: state.time, duration: state.duration) }
            self.onPlaybackChanged?(video, state)
        }
        player.onEnded = { [weak self] _ in
            guard let self else { return }
            if self.autoplay || !self.segments.isEmpty { self.advanceQueue() }
        }
    }

    // MARK: Lifecycle

    func start() async {
        WatchTogether.shared.configure(model: self)
        await feed.seedIfNeeded()
        _ = try? await store.purgeWatchLater(olderThan: clearAfterWeeks)
        observeLibrary()
        await refresh()
    }

    func refresh(force: Bool = false) async {
        isRefreshing = true
        await feed.refreshSubscriptions(force: force)
        isRefreshing = false
    }

    private func observeLibrary() {
        observers.forEach { $0.cancel() }
        let liked = store.values { db in try Q.likedIds(db) }
        let later = store.values { db in try Q.watchLaterIds(db) }
        observers = [
            Task { [weak self] in
                do { for try await ids in liked { self?.likedIds = ids } } catch {}
            },
            Task { [weak self] in
                do { for try await ids in later { self?.watchLaterIds = ids } } catch {}
            },
        ]
    }

    // MARK: Playback

    func open(_ video: Video, at start: Double? = nil, present: Bool = true) {
        segments = []
        if let from = playingFrom, from.position(of: video.id) == nil { playingFrom = nil }
        activeSegmentEnd = nil
        Task {
            var resume = start ?? 0
            if start == nil, let h = try? await store.read({ db in try HistoryEntry.fetchOne(db, key: video.id) }), h.progress < 0.95 {
                resume = h.positionSeconds
            }
            player.load(video, at: resume)
            if video.durationSeconds == nil { await feed.enrich(videoIds: [video.id]) }
        }
        if present {
            #if os(iOS)
            if mode == .music { showMusicPlayer = true } else { watching = video }
            #else
            watching = video
            #endif
        }
        updatePalette(for: video)
    }

    /// Plays a list in order and remembers where it came from.
    func play(list videos: [Video], from title: String, playlistId: String? = nil, startingAt index: Int = 0) {
        guard videos.indices.contains(index) else { return }
        playingFrom = PlayingFrom(title: title, playlistId: playlistId, videos: videos)
        player.queue = Array(videos.dropFirst(index + 1))
        open(videos[index])
    }

    func play(segments: [QueueSegment]) {
        guard let first = segments.first else { return }
        self.segments = Array(segments.dropFirst())
        activeSegmentEnd = first.end
        player.load(first.video, at: first.start)
        watching = first.video
        updatePalette(for: first.video)
    }

    /// Called from the time observer: stops a time-box chapter at its end.
    func tick(_ state: PlayerEngine.State) {
        if let end = activeSegmentEnd, state.time >= end - 0.3 { advanceQueue() }
        WatchTogether.shared.localStateChanged(isPlaying: state.isPlaying, time: state.time)
    }

    func advanceQueue() {
        if let next = segments.first {
            segments.removeFirst()
            activeSegmentEnd = next.end
            player.load(next.video, at: next.start)
            if watching != nil { watching = next.video }
            updatePalette(for: next.video)
        } else if player.playNextInQueue() {
            activeSegmentEnd = nil
        } else {
            if activeSegmentEnd != nil, !player.state.ended { player.pause() }
            activeSegmentEnd = nil
        }
    }

    func updatePalette(for video: Video) {
        guard tintFromVideo else { palette = .standard; return }
        Task {
            if let p = await VideoPalette.extract(from: video.bestThumbnail) {
                withAnimation(.easeInOut(duration: 0.6)) { palette = p }
            }
        }
    }

    // MARK: Library actions

    func toggleWatchLater(_ id: String) {
        let adding = !watchLaterIds.contains(id)
        Task { try? await store.toggleWatchLater(id) }
        flash(adding ? "Saved to Watch later" : "Removed from Watch later")
    }

    func toggleLike(_ id: String) {
        Task { try? await store.toggleLike(id) }
    }

    func subscribe(_ channel: Channel) {
        Task { try? await store.subscribe(channel, music: mode == .music); await feed.refreshSubscriptions(force: true) }
        flash("Subscribed to \(channel.title)")
    }

    func unsubscribe(_ id: String) {
        Task { try? await store.unsubscribe(id) }
    }

    func add(_ videoId: String, to playlist: Playlist) {
        Task { try? await store.add(videoId: videoId, toPlaylist: playlist.id) }
        flash("Added to \(playlist.title)")
    }

    func rememberSearch(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        recentSearches = ([t] + recentSearches.filter { $0.caseInsensitiveCompare(t) != .orderedSame }).prefix(8).map { $0 }
    }

    func flash(_ message: String) {
        withAnimation(.snappy) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { if toast == message { toast = nil } }
        }
    }

    func push(_ route: Route) {
        paths[tab, default: []].append(route)
    }

    // MARK: Deep links: boxtube://watch?v=ID&t=SECONDS, boxtube://timebox, boxtube://music

    func handle(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch url.host {
        case "watch":
            guard let id = items.first(where: { $0.name == "v" })?.value else { return }
            let t = items.first(where: { $0.name == "t" })?.value.flatMap(Double.init)
            Task { if let v = await feed.ensureVideo(id) { open(v, at: t) } }
        case "timebox": showTimeBox = true
        case "music": mode = .music
        default: break
        }
    }
}
