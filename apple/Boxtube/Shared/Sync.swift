import SwiftUI
import BoxtubeCore
import BoxtubeUI

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
        Task {
            try? await store.setDisliked(id, on)
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

    /// Removes a playlist from Boxtube; with `onYouTube` (sync on) it's deleted from your YouTube account too.
    func deletePlaylist(_ playlist: Playlist, onYouTube: Bool) {
        let both = onYouTube && syncEnabled
        Task {
            try? await store.deletePlaylist(playlist.id, onYouTube: both)
            if both { scheduleSync() }
        }
        flash(both ? "Deleting “\(playlist.title)” on YouTube" : "Removed “\(playlist.title)” from Boxtube")
    }

    /// Makes a Boxtube-only playlist on YouTube (private) and adds its videos, in order.
    func publishPlaylist(_ playlist: Playlist) {
        guard syncEnabled else { return }
        Task {
            let count = (try? await store.publishPlaylist(playlist.id)) ?? 0
            flash("Publishing “\(playlist.title)” with \(count) video\(count == 1 ? "" : "s") to YouTube", seconds: 3)
            scheduleSync()
        }
    }

    func bringBackRemovedPlaylists() async {
        try? await store.unhidePlaylists()
        await importFromYouTube()
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

// MARK: - Playlist deletion and publishing UI

extension View {
    /// Asks how to delete a playlist: on YouTube too (sync on), from Boxtube only, or plainly for Boxtube-only ones.
    func playlistDeleteDialog(_ playlist: Binding<Playlist?>) -> some View { modifier(PlaylistDeleteDialog(playlist: playlist)) }
}

private struct PlaylistDeleteDialog: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(BXMenuHost.self) private var host: BXMenuHost?
    @Binding var playlist: Playlist?

    func body(content: Content) -> some View {
        content.onChange(of: playlist?.id) { _, id in
            guard id != nil, let p = playlist else { return }
            host?.show(dialog(for: p))
        }
    }

    private func dialog(for p: Playlist) -> BXDialog {
        let done: @MainActor () -> Void = { playlist = nil }
        let delete: (Bool) -> BXDialog.Action = { onYouTube in
            .init(title: "", kind: .destructive) { _ in model.deletePlaylist(p, onYouTube: onYouTube); playlist = nil }
        }
        if Store.isLocalPlaylist(p.id) {
            var d = delete(false); d.title = "Delete"
            return .confirm("Delete “\(p.title)”?", message: "This playlist is only in Boxtube.", actions: [d], cancel: done)
        } else if model.syncEnabled {
            var d = delete(true); d.title = "Delete on YouTube too"
            var r = delete(false); r.title = "Remove from Boxtube only"; r.kind = .secondary
            return .confirm("Delete “\(p.title)”?",
                            message: "Deleting on YouTube can't be undone. Removing it from Boxtube only leaves it on YouTube; Settings can bring it back.",
                            actions: [d, r], cancel: done)
        } else {
            var d = delete(false); d.title = "Remove from Boxtube"
            return .confirm("Delete “\(p.title)”?", message: "It stays on YouTube. Settings can bring it back.", actions: [d], cancel: done)
        }
    }
}

extension AppModel {
    /// The actions for one playlist, shared by its ⋯ menu and its right-click / long-press menu.
    @BXMenuBuilder
    func playlistMenu(_ summary: PlaylistSummary, publishing: Bool, toDelete: Binding<Playlist?>, toPublish: Binding<PlaylistSummary?>) -> [BXMenuSection] {
        let p = summary.playlist
        BXMenuSection {
            BXMenuItem(p.isMusic ? "Remove from Music" : "Show in Music", icon: p.isMusic ? "music.note.slash" : "music.note", tint: Color(hex: 0xB3A1FF)) {
                Task { try? await self.store.setPlaylistMusic(p.id, !p.isMusic) }
            }
            if syncEnabled, Store.isLocalPlaylist(p.id), !publishing {
                BXMenuItem("Publish to YouTube…", icon: "arrow.up.circle") { toPublish.wrappedValue = summary }
            }
        }
        BXMenuSection {
            BXMenuItem("Delete…", icon: "trash", destructive: true) { toDelete.wrappedValue = p }
        }
    }
}

/// The ⋯ button on a playlist card.
struct PlaylistMoreButton: View {
    @Environment(AppModel.self) private var model
    var summary: PlaylistSummary
    var publishing: Bool
    @Binding var toDelete: Playlist?
    @Binding var toPublish: PlaylistSummary?

    var body: some View {
        BXMenuButton(trailing: true) {
            model.playlistMenu(summary, publishing: publishing, toDelete: $toDelete, toPublish: $toPublish)
        } label: {
            MoreDots(size: 16)
                .foregroundStyle(BX.muted)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .fixedSize()
        .accessibilityLabel("More for \(summary.playlist.title)")
        #if os(macOS)
        .help("More")
        #endif
    }
}

extension View {
    /// Confirms publishing a Boxtube-only playlist, with what it costs.
    func playlistPublishDialog(_ summary: Binding<PlaylistSummary?>) -> some View { modifier(PlaylistPublishDialog(summary: summary)) }
}

private struct PlaylistPublishDialog: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(BXMenuHost.self) private var host: BXMenuHost?
    @Binding var summary: PlaylistSummary?

    func body(content: Content) -> some View {
        content.onChange(of: summary?.id) { _, id in
            guard id != nil, let s = summary else { return }
            let units = 50 * (1 + s.count)
            let message = "Creates a private playlist on your channel and adds \(s.count) video\(s.count == 1 ? "" : "s"). Uses about \(units.formatted()) of your 10,000 daily quota units\(units > 10_000 - model.quotaToday ? "; the rest continues tomorrow" : "")."
            host?.show(.confirm("Publish “\(s.playlist.title)” to YouTube?", message: message,
                                actions: [.init(title: "Publish", kind: .primary) { _ in model.publishPlaylist(s.playlist); summary = nil }],
                                cancel: { summary = nil }))
        }
    }
}

/// "Publish to YouTube" for a playlist that's only in Boxtube (its header), with what it costs.
struct PublishPlaylistButton: View {
    @Environment(AppModel.self) private var model
    var playlist: Playlist
    var videoCount: Int
    var compact = false
    @State private var publishing: Set<String> = []
    @State private var confirming: PlaylistSummary?

    var body: some View {
        Group {
            if model.syncEnabled, Store.isLocalPlaylist(playlist.id), !publishing.contains(playlist.id) {
                Button { confirming = PlaylistSummary(playlist: playlist, count: videoCount, cover: nil) } label: {
                    Label("Publish to YouTube", systemImage: "arrow.up.circle")
                        .font(.system(size: compact ? 13 : 14.5, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: compact ? 32 : 44)
                        .frame(maxWidth: compact ? nil : .infinity)
                        .background(BX.surface3, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .playlistPublishDialog($confirming)
        .observing(model.store, { db in try Q.publishingPlaylists(db) }) { publishing = $0 }
    }
}
