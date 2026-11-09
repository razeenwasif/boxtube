import SwiftUI
import BoxtubeCore
import BoxtubeUI

extension View {
    /// Mac: the card lifts a little on hover and shows an info button; clicking it flips the card over to
    /// the video's details and description. It flips back when the pointer leaves. Nothing on iPhone.
    @ViewBuilder
    func flipCard(_ video: Video, cornerRadius: CGFloat, channelAvatar: URL? = nil) -> some View {
        #if os(macOS)
        modifier(FlipCard(video: video, cornerRadius: cornerRadius, avatar: channelAvatar))
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct FlipCard: ViewModifier {
    @Environment(AppModel.self) private var model
    var video: Video
    var cornerRadius: CGFloat
    var avatar: URL?

    @State private var hovering = false
    @State private var flipped = false
    @State private var backShown = false
    @State private var flipBack: Task<Void, Never>?
    /// Set once a missing description has been asked for, so the back can then say there isn't one.
    @State private var fetched = false

    private static let flipDuration = 0.42

    func body(content: Content) -> some View {
        content
            // Front: hidden at the half-way point of the turn, and out of the way while the back shows.
            .opacity(flipped ? 0 : 1)
            .animation(.linear(duration: 0.001).delay(Self.flipDuration / 2), value: flipped)
            .allowsHitTesting(!flipped)
            .accessibilityHidden(flipped)
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .overlay {
                // Only exists while showing or turning, so its buttons can't be reached from the front.
                if backShown {
                    VideoInfoBack(video: video, avatar: avatar, cornerRadius: cornerRadius, fetched: fetched) { setFlipped(false) }
                        .opacity(flipped ? 1 : 0)
                        .animation(.linear(duration: 0.001).delay(Self.flipDuration / 2), value: flipped)
                        .allowsHitTesting(flipped)
                        .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                }
            }
            .overlay(alignment: .topTrailing) {
                if hovering && !flipped {
                    FlipButton(systemImage: "info", label: "Show details for \(video.title)") { setFlipped(true) }
                        .padding(8)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            // Pops out over its neighbours: bigger, with a deeper shadow, drawn on top.
            .scaleEffect(hovering ? 1.08 : 1)
            .shadow(color: .black.opacity(hovering ? 0.55 : 0), radius: hovering ? 26 : 0, y: hovering ? 16 : 0)
            .zIndex(hovering || flipped ? 1 : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: hovering)
            .onHover { inside in
                hovering = inside
                flipBack?.cancel()
                // Leaving a flipped card turns it back, after a moment in case the pointer slips off.
                if !inside, flipped {
                    flipBack = Task {
                        try? await Task.sleep(for: .seconds(0.6))
                        if !Task.isCancelled { setFlipped(false) }
                    }
                }
            }
    }

    private func setFlipped(_ on: Bool) {
        guard on != flipped else { return }
        if on {
            model.preview.leave(video.id)
            // Videos from channel feeds can arrive without their description; fetch it on demand.
            if video.summary.isEmpty, model.hasAPIKey, !fetched {
                Task {
                    await model.feed.enrich(videoIds: [video.id])
                    fetched = true
                }
            }
        }
        let turn = Animation.spring(duration: Self.flipDuration, bounce: 0.18)
        if on {
            // Put the back in place (turned away) first, then turn, so the turn animates.
            backShown = true
            DispatchQueue.main.async { withAnimation(turn) { flipped = true } }
        } else {
            withAnimation(turn) { flipped = false } completion: { if !flipped { backShown = false } }
        }
    }
}

/// The round button that turns a card over.
private struct FlipButton: View {
    var systemImage: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.62), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The back of a card: who made it, how long it is, and what it's about.
private struct VideoInfoBack: View {
    @Environment(AppModel.self) private var model
    var video: Video
    var avatar: URL?
    var cornerRadius: CGFloat
    var fetched: Bool
    var flipBack: () -> Void

    var body: some View {
        let meta = video.detailsLine
        let saved = model.watchLaterIds.contains(video.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ChannelAvatar(title: video.channelTitle, url: avatar, size: 22)
                Text(video.channelTitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(BX.text2).lineLimit(1)
                Spacer(minLength: 0)
                FlipButton(systemImage: "arrow.uturn.backward", label: "Back to the thumbnail", action: flipBack)
            }
            Text(video.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(meta).font(.system(size: 11.5)).foregroundStyle(BX.muted).lineLimit(1)
            if let why = model.recommendationReasons[video.id] {
                Label(why, systemImage: "sparkles")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(BX.coralText)
                    .lineLimit(1)
            }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            ScrollView {
                Text(description)
                    .font(.system(size: 12.5))
                    .lineSpacing(2)
                    .foregroundStyle(video.summary.isEmpty ? BX.muted : BX.text2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            HStack(spacing: 8) {
                Button { model.open(video) } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BX.coralInk)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(BX.coral, in: Capsule())
                }
                Button { model.toggleWatchLater(video.id) } label: {
                    // Just the icon when the card is too narrow for the words.
                    ViewThatFits(in: .horizontal) {
                        Label(saved ? "Saved" : "Watch later", systemImage: saved ? "checkmark" : "clock")
                            .padding(.horizontal, 12)
                        Image(systemName: saved ? "checkmark" : "clock")
                            .frame(width: 28)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: 28)
                    .background(.white.opacity(0.08), in: Capsule())
                }
                .help(saved ? "Saved to Watch later" : "Save to Watch later")
                .accessibilityLabel(saved ? "Remove from Watch later" : "Save to Watch later")
                Spacer(minLength: 0)
                VideoMoreButton(video: video, size: 14)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BX.surface2, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }

    private var description: String {
        if !video.summary.isEmpty { return video.summary }
        if !model.hasAPIKey { return "No description here. Add an API key to load descriptions." }
        return fetched ? "This video has no description." : "Loading the description…"
    }
}
#endif
