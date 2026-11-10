import SwiftUI
import BoxtubeCore
import BoxtubeUI

extension Video {
    /// Views · age · length · chapters, as shown on a card's details.
    var detailsLine: String {
        let chapters = self.chapters
        return [Format.views(viewCount), Format.ago(publishedAt), durationSeconds.map { Format.minutes(Double($0)) },
                chapters.isEmpty ? nil : "\(chapters.count) chapters"].compactMap { $0 }.joined(separator: " · ")
    }
}

#if os(iOS)
/// A long press on a video brings up its details card (`VideoPeek`), the iPhone counterpart of the
/// Mac's flip cards. It's presented as a clear full-screen cover so it also works over the Watch screen.
struct VideoPeekTrigger: ViewModifier {
    @Environment(AppModel.self) private var model
    var video: Video
    @State private var presented = false
    @State private var playAfter = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in show() })
            .accessibilityAction(named: "Show details") { show() }
            .fullScreenCover(isPresented: $presented, onDismiss: {
                model.peekShowing = false
                // Play once the cover is gone, so the Watch screen isn't presented on top of a closing one.
                if playAfter { playAfter = false; model.open(video) }
            }) {
                VideoPeek(video: video) { play in
                    playAfter = play
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { presented = false }
                }
                .environment(model)
                .presentationBackground(.clear)
            }
    }

    private func show() {
        guard !presented else { return }
        model.peekShowing = true
        // The card animates itself in; skip the cover's slide-up.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { presented = true }
    }
}

/// The details card: thumbnail, who made it, why Home picked it and the description, with Play and Watch later.
struct VideoPeek: View {
    @Environment(AppModel.self) private var model
    var video: Video
    var close: (_ play: Bool) -> Void

    @State private var shown = false
    @State private var live: Video?
    @State private var channel: Channel?
    /// Set once a missing description has been asked for, so the card can then say there isn't one.
    @State private var fetched = false

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.35))
                .background(.ultraThinMaterial)
                .opacity(shown ? 1 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss(play: false) }
                .accessibilityLabel("Close details")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { dismiss(play: false) }
            if shown {
                card
                    .padding(.horizontal, 18)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.impact(weight: .medium), trigger: shown) { _, now in now }
        .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { shown = true } }
        .observing(model.store, id: video.id, { [id = video.id] db in try Q.video(db, id) }) { live = $0 }
        .observing(model.store, id: video.channelId, { [id = video.channelId] db in try Channel.fetchOne(db, key: id) }) { channel = $0 }
        .task(id: video.id) {
            // Videos from channel feeds can arrive without their description; fetch it on demand.
            guard video.summary.isEmpty, model.hasAPIKey, !fetched else { return }
            await model.feed.enrich(videoIds: [video.id])
            fetched = true
        }
    }

    private var card: some View {
        let v = live ?? video
        let saved = model.watchLaterIds.contains(v.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button { dismiss(play: true) } label: {
                VideoThumbnail(v, radius: 16, progress: model.progressById[v.id])
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(v.title)")
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ChannelAvatar(title: v.channelTitle, url: channel?.avatarURL, size: 24)
                    Text(v.channelTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(BX.text2).lineLimit(1)
                }
                Text(v.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BX.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(v.detailsLine).font(.system(size: 12.5)).foregroundStyle(BX.muted).lineLimit(1)
                if let why = model.recommendationReasons[v.id] {
                    Label(why, systemImage: "sparkles")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(BX.coralText)
                        .lineLimit(2)
                }
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                // Short descriptions sit as they are; long ones scroll inside the card.
                ViewThatFits(in: .vertical) {
                    descriptionText(v)
                    ScrollView { descriptionText(v) }.scrollIndicators(.visible)
                }
                .frame(maxHeight: 230)
                HStack(spacing: 10) {
                    Button { dismiss(play: true) } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BX.coralInk)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(BX.coral, in: Capsule())
                    }
                    Button { model.toggleWatchLater(v.id) } label: {
                        Label(saved ? "Saved" : "Watch later", systemImage: saved ? "checkmark" : "clock")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BX.text)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    .accessibilityLabel(saved ? "Remove from Watch later" : "Save to Watch later")
                    Button {
                        // With nothing playing, queueing just plays it (after this card closes).
                        if model.player.video == nil { dismiss(play: true) } else { model.addToQueue(v); dismiss(play: false) }
                    } label: {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(BX.text)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .accessibilityLabel("Add to queue")
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(maxWidth: 420)
        .background(BX.surface2, in: .rect(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
    }

    private func descriptionText(_ v: Video) -> some View {
        Text(description(v))
            .font(.system(size: 13.5))
            .lineSpacing(2)
            .foregroundStyle(v.summary.isEmpty ? BX.muted : BX.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func description(_ v: Video) -> String {
        if !v.summary.isEmpty { return v.summary }
        if !model.hasAPIKey { return "No description here. Add an API key to load descriptions." }
        return fetched ? "This video has no description." : "Loading the description…"
    }

    private func dismiss(play: Bool) {
        if play { model.peekShowing = false }
        withAnimation(.easeOut(duration: 0.16)) { shown = false } completion: { close(play) }
    }
}
#endif
