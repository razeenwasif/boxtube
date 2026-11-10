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
/// Used by every video's ⋯ button and its right-click menu (Mac).
extension AppModel {
    @BXMenuBuilder
    func videoMenu(_ video: Video) -> [BXMenuSection] {
        let saved = watchLaterIds.contains(video.id)
        let liked = likedIds.contains(video.id)
        let watched = (progressById[video.id] ?? 0) >= 0.9
        let following = channelIsSubscribed(video.channelId)

        if let why = recommendationReasons[video.id] {
            // Why Home picked it; shown as a line, not an action.
            BXMenuItem.note(why)
        }
        BXMenuSection {
            BXMenuItem("Play next", icon: "text.line.first.and.arrowtriangle.forward") { self.playNext(video) }
            BXMenuItem("Add to queue", icon: "text.badge.plus") { self.addToQueue(video) }
        }
        BXMenuSection {
            BXMenuItem(saved ? "Remove from Watch later" : "Save to Watch later", icon: saved ? "clock.badge.xmark" : "clock", tint: BX.amber) {
                self.toggleWatchLater(video.id)
            }
            playlistSubmenu(video)
            BXMenuItem(liked ? "Unlike" : "Like", icon: liked ? "hand.thumbsup.fill" : "hand.thumbsup") { self.toggleLike(video.id) }
        }
        BXMenuSection {
            BXMenuItem.share(video.watchURL)
            BXMenuItem("Copy link", icon: "link") { self.copyLink(video) }
            BXMenuItem("Open on YouTube", icon: "arrow.up.forward.app") { openExternally(video.watchURL) }
        }
        BXMenuSection {
            BXMenuItem(watched ? "Mark as unwatched" : "Mark as watched", icon: watched ? "eye.slash" : "eye") { self.setWatched(video, !watched) }
            BXMenuItem("Not interested", icon: "nosign") { self.notInterested(video) }
            if !following {
                BXMenuItem("Don't recommend channel", icon: "minus.circle") { self.dontRecommend(video) }
            }
            BXMenuItem("Go to \(video.channelTitle)", icon: "person.crop.square") { self.goToChannel(video.channelId) }
        }
    }

    /// "Save to playlist" with your playlists inside.
    func playlistSubmenu(_ video: Video, title: String = "Save to playlist") -> BXMenuItem {
        .submenu(title, icon: "music.note.list") {
            BXMenuSection("Your playlists") {
                if playlistsCache.isEmpty { BXMenuItem.note("No playlists yet", icon: "music.note.list", tint: BX.muted) }
                for p in playlistsCache {
                    BXMenuItem(p.playlist.title, icon: p.playlist.isMusic ? "music.note" : "list.bullet") { self.add(video.id, to: p.playlist) }
                }
            }
        }
    }
}

/// Opens a link in the browser (or the YouTube app).
@MainActor
func openExternally(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.open(url)
    #else
    UIApplication.shared.open(url)
    #endif
}

/// The ⋯ button on a video card or row.
struct VideoMoreButton: View {
    @Environment(AppModel.self) private var model
    var video: Video
    var vertical = true
    var size: CGFloat = 16

    var body: some View {
        BXMenuButton(trailing: true) {
            model.videoMenu(video)
        } label: {
            MoreDots(vertical: vertical, size: size)
                .foregroundStyle(BX.muted)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
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
            BXActionRow(title: "Show hidden \(parts.joined(separator: " and ")) again", icon: "eye") { Task { try? await model.store.unhideAll() } }
        }
    }
    private func count(_ n: Int, _ word: String) -> String? { n == 0 ? nil : "\(n) \(word)\(n == 1 ? "" : "s")" }
}
