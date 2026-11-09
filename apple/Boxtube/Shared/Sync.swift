import SwiftUI
import BoxtubeCore

/// What two-way sync is doing, for Settings and the You tab.
struct SyncState: Equatable {
    var summary = Q.OutboxSummary()
    var lastSync: Date?
    var problem: String?
    var syncing = false
}

extension AppModel {
    // MARK: Turning sync on and off

    func setSync(_ on: Bool) async {
        guard on else { syncEnabled = false; sync.problem = nil; return }
        guard googleConfigured else { return }
        let canWrite = await google.canWrite
        if account == nil || !canWrite {
            await signInWithGoogle(write: true)
            guard await google.canWrite else {
                flash("Sync needs permission to change your YouTube account. Turn it on to try again.", seconds: 5)
                return
            }
        }
        syncEnabled = true
        await pushLocalOnlySubscriptions()
        await syncNow(importAfter: true)
    }

    /// Channels followed only in Boxtube are subscribed on YouTube too, so mirroring YouTube doesn't drop them.
    private func pushLocalOnlySubscriptions() async {
        guard let token = try? await google.accessToken(),
              let remote = try? await feed.client.mySubscriptions(token: token) else { return }
        let remoteIds = Set(remote.map(\.id))
        let local = (try? await store.read { db in try Q.subscriptions(db).map(\.channel.id) }) ?? []
        let localOnly = local.filter { !remoteIds.contains($0) }
        for id in localOnly { try? await store.enqueue(.subscribe, target: id) }
        if !localOnly.isEmpty { flash("Adding \(localOnly.count) channel\(localOnly.count == 1 ? "" : "s") you follow in Boxtube to YouTube", seconds: 4) }
    }

    // MARK: Sending

    /// Sends waiting changes soon, batching quick runs of taps into one go.
    func scheduleSync() {
        guard syncEnabled else { return }
        syncDebounce?.cancel()
        syncDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.syncNow(importAfter: nil)
        }
    }

    /// Sends the outbox, then brings YouTube's side back in (always when asked, otherwise at most daily).
    func syncNow(importAfter: Bool? = nil) async {
        guard syncEnabled, account != nil, !sync.syncing else { return }
        sync.syncing = true
        defer { sync.syncing = false }
        do {
            let token = try await google.accessToken()
            let report = await syncService.flush(token: token)
            switch report.stoppedBy {
            case .quota: sync.problem = "Today's YouTube quota is used up. Waiting changes go after midnight Pacific time."
            case .needsPermission: sync.problem = "Boxtube can't change your YouTube account. Turn sync off and on to sign in again."
            case .unreachable: sync.problem = "Couldn't reach YouTube. Changes will go when you're back online."
            case nil:
                sync.problem = nil
                sync.lastSync = .now
                let due = lastImport.map { Date.now.timeIntervalSince($0) > 24 * 3600 } ?? true
                if importAfter ?? due { await importFromYouTube(quiet: true) }
            }
        } catch BoxtubeError.notSignedIn(let message) {
            sync.problem = message
        } catch {
            sync.problem = error.localizedDescription
        }
        await recordQuota()
    }

    /// Adds what the API client spent to today's total (YouTube's day starts at midnight Pacific time).
    func recordQuota() async {
        let spent = await feed.client.takeUnitsSpent()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let today = calendar.startOfDay(for: .now)
        if quotaDay != today { quotaDay = today; quotaToday = 0 }
        quotaToday += spent
    }

    // MARK: Changes made in Boxtube

    func toggleLike(_ id: String) {
        let wasLiked = likedIds.contains(id)
        Task {
            try? await store.toggleLike(id)
            await queue(wasLiked ? .unrate : .like, id)
        }
    }

    func setDisliked(_ id: String, _ on: Bool) {
        let liked = likedIds.contains(id)
        Task {
            if on, liked { try? await store.toggleLike(id) }
            await queue(on ? .dislike : .unrate, id)
        }
    }

    func subscribe(_ channel: Channel) {
        Task {
            try? await store.subscribe(channel, music: mode == .music)
            await queue(.subscribe, channel.id)
            await feed.refreshSubscriptions(force: true)
        }
        flash("Subscribed to \(channel.title)")
    }

    func unsubscribe(_ id: String) {
        Task {
            try? await store.unsubscribe(id)
            await queue(.unsubscribe, id)
        }
    }

    func add(_ videoId: String, to playlist: Playlist) {
        Task {
            try? await store.add(videoId: videoId, toPlaylist: playlist.id)
            await queue(.playlistAdd, videoId, playlist: playlist.id)
        }
        flash("Added to \(playlist.title)")
    }

    func remove(_ videoId: String, from playlistId: String) {
        Task {
            try? await store.remove(videoId: videoId, fromPlaylist: playlistId)
            await queue(.playlistRemove, videoId, playlist: playlistId)
        }
    }

    /// New playlists are made on YouTube too while sync is on (private).
    @discardableResult
    func createPlaylist(title: String, music: Bool = false) async -> Playlist? {
        guard let playlist = try? await store.createPlaylist(title: title, music: music) else { return nil }
        await queue(.playlistCreate, playlist.id)
        return playlist
    }

    private func queue(_ kind: OutboxOp.Kind, _ target: String, playlist: String? = nil) async {
        guard syncEnabled else { return }
        try? await store.enqueue(kind, target: target, playlistId: playlist)
        scheduleSync()
    }

    /// One line for Settings and the You tab.
    var syncStatusText: String {
        if sync.syncing { return "Syncing…" }
        if sync.summary.waiting > 0 { return "\(sync.summary.waiting) change\(sync.summary.waiting == 1 ? "" : "s") waiting" }
        if sync.problem != nil { return "Sync paused" }
        if let last = sync.lastSync { return "Up to date · synced \(Format.ago(last))" }
        return "Up to date"
    }

    func retryFailedSync() async {
        try? await store.clearFailedOutbox()
        sync.problem = nil
    }
}
