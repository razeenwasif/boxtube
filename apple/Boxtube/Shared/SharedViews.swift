import SwiftUI
import BoxtubeCore
import BoxtubeUI

// MARK: - Store observation

extension View {
    /// Keeps `into` fed with the latest result of `fetch`; re-subscribes when `id` changes.
    func observing<T: Sendable, ID: Equatable>(
        _ store: Store, id: ID, _ fetch: @escaping @Sendable (Database) throws -> T, into: @escaping @MainActor (T) -> Void
    ) -> some View {
        task(id: id) {
            do {
                for try await value in store.values(fetch) { into(value) }
            } catch {}
        }
    }

    func observing<T: Sendable>(_ store: Store, _ fetch: @escaping @Sendable (Database) throws -> T, into: @escaping @MainActor (T) -> Void) -> some View {
        observing(store, id: 0, fetch, into: into)
    }

    /// Comparable results skip unchanged updates (see `Store.values`).
    func observing<T: Sendable & Equatable, ID: Equatable>(
        _ store: Store, id: ID, _ fetch: @escaping @Sendable (Database) throws -> T, into: @escaping @MainActor (T) -> Void
    ) -> some View {
        task(id: id) {
            do {
                for try await value in store.values(fetch) { into(value) }
            } catch {}
        }
    }

    func observing<T: Sendable & Equatable>(_ store: Store, _ fetch: @escaping @Sendable (Database) throws -> T, into: @escaping @MainActor (T) -> Void) -> some View {
        observing(store, id: 0, fetch, into: into)
    }
}

/// Feeds the player's time to the model. It lives in its own tiny view so the root view doesn't
/// depend on the playback time and re-run several times a second while a video plays.
struct PlaybackTicker: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: model.player.state.time) { _, _ in model.tick(model.player.state) }
            .onChange(of: model.player.isPlaying) { _, _ in model.tick(model.player.state) }
    }
}

// MARK: - Video cards

struct VideoCard: View {
    @Environment(AppModel.self) private var model
    var video: Video
    var progress: Double?
    var showCounts = true
    var muted = false
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { action?() ?? model.open(video) } label: {
                VideoThumbnail(video, radius: 20, progress: progress)
                    .saturation(muted ? 0.45 : 1)
                    .macPreview(video, cornerRadius: 20, enabled: !muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(video.title), \(video.channelTitle)")
            HStack(alignment: .top, spacing: 12) {
                Button { action?() ?? model.open(video) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        if !muted { ChannelAvatar(title: video.channelTitle, size: 36) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(video.title)
                                .font(.system(size: 15.5, weight: .semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(meta).font(.system(size: 12.5)).foregroundStyle(BX.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if muted, let d = video.durationSeconds {
                            Text(Format.minutes(Double(d))).font(.system(size: 13, weight: .semibold)).foregroundStyle(BX.muted)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
                VideoMoreButton(video: video).padding(.top, -4)
            }
            .padding(.leading, 4)
        }
        .flipCard(video, cornerRadius: 20)
        .videoContextMenu(video)
    }

    private var meta: String {
        let parts = showCounts ? [video.channelTitle, Format.views(video.viewCount), Format.ago(video.publishedAt)] : [video.channelTitle, Format.ago(video.publishedAt)]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

struct VideoRow: View {
    @Environment(AppModel.self) private var model
    var video: Video
    var thumbWidth: CGFloat = 152
    var subtitle: String?
    var progress: Double?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Button { action?() ?? model.open(video) } label: {
                HStack(alignment: .top, spacing: 12) {
                    VideoThumbnail(video, radius: 12, progress: progress)
                        .frame(width: thumbWidth)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title).font(.system(size: 14, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Text(video.channelTitle).font(.system(size: 12)).foregroundStyle(BX.muted)
                        Text(subtitle ?? [Format.views(video.viewCount), Format.ago(video.publishedAt)].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(BX.muted)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VideoMoreButton(video: video).padding(.top, -4)
        }
        .videoContextMenu(video)
    }
}

struct ShortCard: View {
    var video: Video
    var width: CGFloat = 136
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                VideoThumbnail(video, radius: 0, showDuration: false, aspect: 9 / 16)
                LinearGradient(colors: [.black.opacity(0.78), .clear], startPoint: .bottom, endPoint: .top)
                    .frame(height: 96)
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title).font(.system(size: 13, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    if let views = Format.views(video.viewCount) {
                        Text(views).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .foregroundStyle(.white)
                .padding(10)
            }
            .frame(width: width, height: width * 240 / 136)
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(video.title)
    }
}

// MARK: - Context menu shared by every video

struct VideoMenu: ViewModifier {
    var video: Video

    func body(content: Content) -> some View {
        content.contextMenu {
            VideoActions(video: video)
        } preview: {
            VStack(alignment: .leading, spacing: 8) {
                VideoThumbnail(video, radius: 12)
                Text(video.title).font(.headline).lineLimit(2)
                Text(video.channelTitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 320)
        }
    }
}

extension View {
    func videoContextMenu(_ video: Video) -> some View { modifier(VideoMenu(video: video)) }
}

// MARK: - Empty / hint states

struct HintCard: View {
    var icon: String
    var title: String
    var message: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(BX.coralText)
                .frame(width: 36, height: 36).background(BX.coral.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14.5, weight: .bold))
                Text(message).font(.system(size: 13)).foregroundStyle(BX.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .boxCard(18)
    }
}

struct Toast: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13.5, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 11)
            .boxGlass(Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityAddTraits(.isStaticText)
    }
}
