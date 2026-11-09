import SwiftUI
import BoxtubeCore
import BoxtubeUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension AppModel {
    /// Plays right after the current video (or now, if nothing is playing).
    func playNext(_ video: Video) {
        guard player.video != nil else { open(video); return }
        userQueue.removeAll { $0.id == video.id }
        userQueue.insert(video, at: 0)
        flash("Playing next")
    }

    /// Plays after everything already queued (or now, if nothing is playing).
    func addToQueue(_ video: Video) {
        guard player.video != nil else { open(video); return }
        userQueue.removeAll { $0.id == video.id }
        userQueue.append(video)
        flash(userQueue.count == 1 ? "Added to queue" : "Added to queue · \(userQueue.count) videos")
    }

    func notInterested(_ video: Video) {
        Task { try? await store.hideVideo(video.id) }
        flash("You won't see this video in your feeds")
    }

    func dontRecommend(_ video: Video) {
        Task { try? await store.hideChannel(video.channelId) }
        flash("You won't see \(video.channelTitle) in topics or search")
    }

    func setWatched(_ video: Video, _ watched: Bool) {
        Task { try? await store.setWatched(video, watched) }
    }

    func copyLink(_ video: Video) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(video.watchURL.absoluteString, forType: .string)
        #else
        UIPasteboard.general.string = video.watchURL.absoluteString
        #endif
        flash("Link copied")
    }

    func channelIsSubscribed(_ id: String) -> Bool { subscribedIds.contains(id) }

    /// Opens the channel page, leaving the full-screen player if it's up.
    func goToChannel(_ id: String) {
        watching = nil
        #if os(iOS)
        showMusicPlayer = false
        #endif
        push(.channel(id))
    }

    /// Search results and other lists that don't come through the filtered queries.
    func isHidden(_ video: Video) -> Bool {
        hidden.videos.contains(video.id) || hidden.channels.contains(video.channelId)
    }
}

/// Everything you can do with a video, YouTube's card menu plus Boxtube's extras.
/// Used by every video's ⋯ button and its right-click / long-press menu.
struct VideoActions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    var video: Video

    var body: some View {
        let saved = model.watchLaterIds.contains(video.id)
        let liked = model.likedIds.contains(video.id)
        let watched = (model.progressById[video.id] ?? 0) >= 0.9
        let following = model.channelIsSubscribed(video.channelId)

        if let why = model.recommendationReasons[video.id] {
            // Why Home picked it; shown as a label, not an action.
            Section { Label(why, systemImage: "sparkles") }
        }
        Section {
            Button { model.playNext(video) } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { model.addToQueue(video) } label: { Label("Add to queue", systemImage: "text.badge.plus") }
        }
        Section {
            Button { model.toggleWatchLater(video.id) } label: {
                Label(saved ? "Remove from Watch later" : "Save to Watch later", systemImage: saved ? "clock.badge.xmark" : "clock")
            }
            Menu {
                if model.playlistsCache.isEmpty { Text("No playlists yet") }
                ForEach(model.playlistsCache) { p in
                    Button(p.playlist.title) { model.add(video.id, to: p.playlist) }
                }
            } label: { Label("Save to playlist", systemImage: "music.note.list") }
            Button { model.toggleLike(video.id) } label: {
                Label(liked ? "Unlike" : "Like", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
        }
        Section {
            ShareLink(item: video.watchURL) { Label("Share", systemImage: "square.and.arrow.up") }
            Button { model.copyLink(video) } label: { Label("Copy link", systemImage: "link") }
            Button { openURL(video.watchURL) } label: { Label("Open on YouTube", systemImage: "arrow.up.forward.app") }
        }
        Section {
            Button { model.setWatched(video, !watched) } label: {
                Label(watched ? "Mark as unwatched" : "Mark as watched", systemImage: watched ? "eye.slash" : "eye")
            }
            Button { model.notInterested(video) } label: { Label("Not interested", systemImage: "nosign") }
            if !following {
                Button { model.dontRecommend(video) } label: { Label("Don't recommend channel", systemImage: "minus.circle") }
            }
            Button { model.goToChannel(video.channelId) } label: { Label("Go to \(video.channelTitle)", systemImage: "person.crop.square") }
        }
    }
}

/// The ⋯ button on a video card or row.
struct VideoMoreButton: View {
    var video: Video
    var vertical = true
    var size: CGFloat = 16

    var body: some View {
        Menu {
            VideoActions(video: video)
        } label: {
            MoreDots(vertical: vertical, size: size)
                .foregroundStyle(BX.muted)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More for \(video.title)")
        #if os(macOS)
        .help("More")
        #endif
    }
}

/// Settings row that undoes "Not interested" and "Don't recommend channel".
struct HiddenVideosRow: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if !model.hidden.isEmpty {
            let parts = [count(model.hidden.videos.count, "video"), count(model.hidden.channels.count, "channel")].compactMap { $0 }
            Button("Show hidden \(parts.joined(separator: " and ")) again") { Task { try? await model.store.unhideAll() } }
        }
    }
    private func count(_ n: Int, _ word: String) -> String? { n == 0 ? nil : "\(n) \(word)\(n == 1 ? "" : "s")" }
}
