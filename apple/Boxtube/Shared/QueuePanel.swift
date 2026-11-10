import SwiftUI
import BoxtubeCore
import BoxtubeUI

extension AppModel {
    /// Plays a queued video now and takes it out of the queue; the rest stays in order.
    func playFromQueue(_ video: Video) {
        userQueue.removeAll { $0.id == video.id }
        #if os(iOS)
        open(video, present: false)   // the Watch screen follows the player
        #else
        open(video)
        #endif
    }

    func removeFromQueue(_ video: Video) {
        withAnimation(.snappy) { userQueue.removeAll { $0.id == video.id } }
    }

    func clearQueue() {
        withAnimation(.snappy) { userQueue.removeAll() }
    }

    /// Moves a queued video to `index` (clamped), counting positions after it's lifted out.
    func moveInQueue(_ id: String, to index: Int) {
        guard let from = userQueue.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.snappy) {
            let v = userQueue.remove(at: from)
            userQueue.insert(v, at: max(0, min(index, userQueue.count)))
        }
    }

    /// Drop target: puts the dragged video where `target` is now.
    func moveInQueue(_ id: String, onto target: Video) {
        guard id != target.id, let to = userQueue.firstIndex(where: { $0.id == target.id }) else { return }
        moveInQueue(id, to: to)
    }
}

/// The videos you queued with Play next / Add to queue. They play before Up next.
/// Shown on the Watch page only while something is queued.
struct QueuePanel: View {
    @Environment(AppModel.self) private var model
    var thumbWidth: CGFloat = 112
    var muted: Color = BX.muted

    var body: some View {
        let queue = model.userQueue
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Queue").font(.system(size: 16, weight: .bold)).accessibilityAddTraits(.isHeader)
                Text(summary(queue))
                    .font(.system(size: 12.5)).foregroundStyle(muted)
                Spacer()
                Button("Clear") { model.clearQueue() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BX.coral)
            }
            ForEach(Array(queue.enumerated()), id: \.element.id) { i, v in
                row(v, index: i, count: queue.count)
            }
        }
        .padding(14)
    }

    private func summary(_ queue: [Video]) -> String {
        let count = "\(queue.count) video\(queue.count == 1 ? "" : "s")"
        let seconds = queue.compactMap(\.durationSeconds).reduce(0, +)
        return seconds > 0 ? "\(count) · \(Format.minutes(Double(seconds)))" : count
    }

    private func row(_ v: Video, index: Int, count: Int) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(muted)
                .frame(width: 14)
            Button { model.playFromQueue(v) } label: {
                HStack(alignment: .center, spacing: 10) {
                    VideoThumbnail(v, radius: 8).frame(width: thumbWidth)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(v.title).font(.system(size: 13, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Text(v.channelTitle).font(.system(size: 11.5)).foregroundStyle(muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(v.title) now")
            BXMenuButton(trailing: true) {
                BXMenuSection {
                    BXMenuItem("Play now", icon: "play.fill") { model.playFromQueue(v) }
                }
                BXMenuSection {
                    if index > 0 {
                        BXMenuItem("Move to top", icon: "arrow.up.to.line") { model.moveInQueue(v.id, to: 0) }
                        BXMenuItem("Move up", icon: "arrow.up") { model.moveInQueue(v.id, to: index - 1) }
                    }
                    if index < count - 1 {
                        BXMenuItem("Move down", icon: "arrow.down") { model.moveInQueue(v.id, to: index + 1) }
                    }
                }
                BXMenuSection {
                    BXMenuItem("Remove from queue", icon: "minus.circle", destructive: true) { model.removeFromQueue(v) }
                }
            } label: {
                MoreDots(vertical: true, size: 14)
                    .foregroundStyle(muted)
                    .frame(width: 26, height: 30)
                    .contentShape(Rectangle())
            }
            .fixedSize()
            .accessibilityLabel("Queue options for \(v.title)")
            Button { model.removeFromQueue(v) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(muted)
                    .frame(width: 26, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(v.title) from queue")
            #if os(macOS)
            .help("Remove from queue")
            #endif
        }
        .draggable(v.id)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            model.moveInQueue(id, onto: v)
            return true
        }
    }
}

#if os(iOS)
/// The queue on iPhone, from the Watch screen's Queue button: what's playing, what you queued
/// (tap, ⋯, drag to reorder), and what autoplay would pick next, each with a + to queue it.
struct PhoneQueueSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var upNext: [Video]

    var body: some View {
        let queued = Set(model.userQueue.map(\.id))
        let suggestions = upNext.filter { !queued.contains($0.id) && $0.id != model.player.video?.id }.prefix(8)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Queue").font(BX.display(28, .bold)).kerning(-0.6)
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(.bx(.secondary, height: 34))
                }
                .padding(.top, 18)
                if let now = model.player.video {
                    HStack(spacing: 12) {
                        VideoThumbnail(now, radius: 9, showDuration: false).frame(width: 96)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PLAYING NOW").font(.system(size: 10.5, weight: .bold)).kerning(0.8).foregroundStyle(BX.coralText)
                            Text(now.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if model.userQueue.isEmpty {
                    HintCard(icon: "list.bullet", title: "Nothing queued",
                             message: "Tap + below, or choose Play next or Add to queue in any video's ⋯ menu. Queued videos play before autoplay picks.")
                } else {
                    QueuePanel(thumbWidth: 104).cardSurface()
                }
                if !suggestions.isEmpty {
                    Text("Autoplay picks next").font(.system(size: 16, weight: .bold)).padding(.top, 6).accessibilityAddTraits(.isHeader)
                    ForEach(Array(suggestions)) { v in
                        HStack(spacing: 12) {
                            VideoThumbnail(v, radius: 9).frame(width: 104)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(v.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(2)
                                Text(v.channelTitle).font(.system(size: 12)).foregroundStyle(BX.muted).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Button { model.addToQueue(v) } label: {
                                Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(BX.coralInk)
                                    .frame(width: 34, height: 34).background(BX.coral, in: Circle()).contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(v.title) to the queue")
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .foregroundStyle(BX.text)
        .environment(\.colorScheme, .dark)
    }
}
#endif
