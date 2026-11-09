import SwiftUI
#if os(iOS)
import WidgetKit
#endif
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
    let google: GoogleAuth
    let googleConfigured: Bool
    let preview = PreviewController()
    var account: GoogleAccount?
    var isSigningIn = false
    var isImporting = false
    var lastImport: Date? { didSet { defaults.set(lastImport, forKey: "lastImport") } }
    let syncService: SyncService
    var syncEnabled: Bool { didSet { defaults.set(syncEnabled, forKey: "syncEnabled") } }
    var sync = SyncState()
    var quotaToday: Int { didSet { defaults.set(quotaToday, forKey: "quotaToday") } }
    var quotaDay: Date? { didSet { defaults.set(quotaDay, forKey: "quotaDay") } }
    @ObservationIgnored var syncDebounce: Task<Void, Never>?

    // Settings
    var calmMode: Bool { didSet { defaults.set(calmMode, forKey: "calmMode"); if calmMode { preview.stop() } } }
    var mode: AppMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    var clearAfterWeeks: Int { didSet { defaults.set(clearAfterWeeks, forKey: "clearAfterWeeks") } }
    var tintFromVideo: Bool { didSet { defaults.set(tintFromVideo, forKey: "tintFromVideo") } }
    var displayName: String { didSet { defaults.set(displayName, forKey: "displayName") } }
    var autoplay: Bool { didSet { defaults.set(autoplay, forKey: "autoplay") } }
    var previewMode: PreviewMode {
        didSet { defaults.set(previewMode.rawValue, forKey: "previewMode"); if previewMode == .off { preview.stop() } }
    }

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
    /// Videos you chose with Play next / Add to queue; they play before Autoplay's picks.
    var userQueue: [Video] = []
    var playlistsCache: [PlaylistSummary] = []
    var progressById: [String: Double] = [:]
    var hidden = Q.HiddenSets()
    var subscribedIds: Set<String> = []
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

    @ObservationIgnored private lazy var nowPlaying = NowPlaying(model: self)
    private let defaults = UserDefaults.standard
    private var observers: [Task<Void, Never>] = []

    init() {
        BoxtubeFonts.register()
        BoxtubeImages.configure()
        let key = Bundle.main.object(forInfoDictionaryKey: "YouTubeAPIKey") as? String
        let store = (try? Store.live()) ?? (try! Store.inMemory())
        let client = YouTubeClient(apiKey: key)
        self.store = store
        self.feed = FeedService(store: store, client: client)
        self.syncService = SyncService(store: store, youtube: client)
        self.hasAPIKey = client.hasKey
        let google = GoogleAuth(clientID: Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String,
                                clientSecret: Bundle.main.object(forInfoDictionaryKey: "GoogleClientSecret") as? String)
        self.google = google
        self.googleConfigured = google.isConfigured
        self.player = PlayerEngine()
        calmMode = defaults.bool(forKey: "calmMode")
        mode = AppMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .videos
        clearAfterWeeks = defaults.object(forKey: "clearAfterWeeks") as? Int ?? 4
        tintFromVideo = defaults.object(forKey: "tintFromVideo") as? Bool ?? true
        displayName = defaults.string(forKey: "displayName") ?? "Jordan Diaz"
        autoplay = defaults.object(forKey: "autoplay") as? Bool ?? true
        syncEnabled = defaults.bool(forKey: "syncEnabled")
        quotaToday = defaults.integer(forKey: "quotaToday")
        quotaDay = defaults.object(forKey: "quotaDay") as? Date
        lastImport = defaults.object(forKey: "lastImport") as? Date
        #if os(iOS)
        previewMode = PreviewMode(rawValue: defaults.string(forKey: "previewMode") ?? "") ?? .wifiOnly
        #else
        previewMode = PreviewMode(rawValue: defaults.string(forKey: "previewMode") ?? "") ?? .on
        #endif
        recentSearches = defaults.stringArray(forKey: "recentSearches") ?? []

        player.onProgress = { [weak self] video, state in
            guard let self else { return }
            Task { try? await self.store.recordProgress(videoId: video.id, position: state.time, duration: state.duration) }
            self.onPlaybackChanged?(video, state)
        }
        player.onEnded = { [weak self] _ in
            guard let self else { return }
            if self.autoplay || !self.segments.isEmpty || !self.userQueue.isEmpty { self.advanceQueue() }
        }
        preview.attach(self)
    }

    // MARK: Lifecycle

    func start() async {
        WatchTogether.shared.configure(model: self)
        await feed.seedIfNeeded()
        #if os(iOS)
        WidgetCenter.shared.reloadAllTimelines() // so widgets redraw after an app update
        #endif
        account = await google.account
        if syncEnabled {
            Task { await syncNow() }
            // While changes are waiting (offline, or out of quota), try again every few minutes.
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(300))
                    guard let self else { return }
                    if self.syncEnabled, self.sync.summary.waiting > 0 { await self.syncNow(importAfter: false) }
                }
            }
        }
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
        let outbox = store.values { db in try Q.outboxSummary(db) }
        let lists = store.values { db in try Q.playlists(db) }
        let progress = store.values { db in try Q.progress(db) }
        let hiddenSets = store.values { db in try Q.hidden(db) }
        let following = store.values { db in Set(try String.fetchAll(db, sql: "SELECT id FROM channel WHERE isSubscribed = 1")) }
        observers = [
            Task { [weak self] in
                do { for try await ids in liked { self?.likedIds = ids } } catch {}
            },
            Task { [weak self] in
                do { for try await ids in later { self?.watchLaterIds = ids } } catch {}
            },
            Task { [weak self] in
                do { for try await summary in outbox { self?.sync.summary = summary } } catch {}
            },
            Task { [weak self] in
                do { for try await value in lists { self?.playlistsCache = value } } catch {}
            },
            Task { [weak self] in
                do { for try await value in progress { self?.progressById = value } } catch {}
            },
            Task { [weak self] in
                do { for try await value in hiddenSets { self?.hidden = value } } catch {}
            },
            Task { [weak self] in
                do { for try await value in following { self?.subscribedIds = value } } catch {}
            },
        ]
    }

    // MARK: Playback

    func open(_ video: Video, at start: Double? = nil, present: Bool = true) {
        // Opening a card that's previewing carries on from the preview's moment.
        let start = start ?? preview.handoffTime(for: video.id)
        preview.stop()
        segments = []
        userQueue.removeAll { $0.id == video.id }
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
        nowPlaying.update(video: player.video, state: state)
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
        } else if !userQueue.isEmpty {
            let next = userQueue.removeFirst()
            activeSegmentEnd = nil
            player.load(next)
            if watching != nil { watching = next }
            updatePalette(for: next)
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





    func rememberSearch(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        recentSearches = ([t] + recentSearches.filter { $0.caseInsensitiveCompare(t) != .orderedSame }).prefix(8).map { $0 }
    }

    func flash(_ message: String, seconds: Double = 2) {
        withAnimation(.snappy) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
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
