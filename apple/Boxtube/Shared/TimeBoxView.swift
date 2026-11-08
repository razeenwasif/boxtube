import SwiftUI
import BoxtubeCore
import BoxtubeUI

/// Idea 01: "I have N minutes" → a box of videos (or single chapters) that fills it.
struct TimeBoxView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Double = 25
    @State private var useWatchLater = true
    @State private var useSubscriptions = true
    @State private var seed = 0
    @State private var later: [WatchLaterRow] = []
    @State private var feed: [Video] = []
    @State private var progress: [String: Double] = [:]

    private let presets: [Double] = [10, 25, 45, 60]

    var body: some View {
        let box = makeBox()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        LargeTitle("Time box", size: 28)
                        Text("How long have you got?").font(.system(size: 13.5)).foregroundStyle(BX.muted)
                    }
                    Spacer()
                    CircleIconButton("xmark", label: "Close", size: 36, fill: BX.surface3) { dismiss() }
                }

                Dial(minutes: $minutes)
                    .frame(width: 220, height: 220)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { p in
                        Button { withAnimation(.snappy) { minutes = p } } label: {
                            Text(p >= 60 ? "1h" : "\(Int(p))m")
                                .font(.system(size: 13, weight: minutes == p ? .bold : .semibold))
                                .padding(.horizontal, 14).frame(height: 32)
                                .foregroundStyle(minutes == p ? BX.coralText : BX.text2)
                                .background(minutes == p ? BX.coral.opacity(0.18) : BX.surface3, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    Text("Fill from").font(.system(size: 12.5)).foregroundStyle(BX.muted)
                    SourceToggle(title: "Watch later", isOn: $useWatchLater)
                    SourceToggle(title: "Subscriptions", isOn: $useSubscriptions)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Your box").font(.system(size: 15, weight: .bold))
                        Spacer()
                        Text("\(Format.clock(box.total)) of \(Format.clock(minutes * 60))").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(BX.muted)
                    }
                    if box.picks.isEmpty {
                        Text(model.hasAPIKey ? "Nothing fits yet. Save a few videos to Watch later." : "Time boxes need video lengths. Add a YouTube API key, or play videos once so Boxtube learns their length.")
                            .font(.system(size: 13)).foregroundStyle(BX.muted)
                    } else {
                        GeometryReader { geo in
                            HStack(spacing: 3) {
                                ForEach(box.picks) { p in
                                    ArtPalette.forSeed(p.video.id).circle
                                        .frame(width: max(4, (geo.size.width - CGFloat(box.picks.count) * 3) * CGFloat(p.length / (minutes * 60))))
                                }
                                BX.surface3
                            }
                            .clipShape(Capsule())
                        }
                        .frame(height: 10)
                        ForEach(box.picks) { p in
                            HStack(spacing: 11) {
                                VideoThumbnail(p.video, radius: 8, showDuration: false).frame(width: 74)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.video.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(p.reason).font(.system(size: 11.5)).foregroundStyle(BX.muted).lineLimit(1)
                                }
                                Spacer()
                                Text(Format.clock(p.length)).font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(BX.text2)
                            }
                        }
                    }
                }
                .padding(14)
                .boxCard(22, fill: BX.surface2)

                HStack(spacing: 10) {
                    Button {
                        model.play(segments: box.picks.map { QueueSegment(video: $0.video, start: $0.start, end: $0.start == 0 && $0.end == Double($0.video.durationSeconds ?? 0) ? nil : $0.end) })
                        dismiss()
                    } label: {
                        Label("Play box", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .foregroundStyle(BX.coralInk)
                            .background(BX.coral, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(box.picks.isEmpty)
                    Button { withAnimation(.snappy) { seed += 1 } } label: {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 18, weight: .semibold))
                            .frame(width: 52, height: 52).background(BX.surface3, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Build a different box")
                }
            }
            .padding(20)
        }
        .background(Color(hex: 0x121215))
        .observing(model.store, { db in try Q.watchLater(db) }) { later = $0 }
        .observing(model.store, { db in try Q.feed(db, limit: 80) }) { feed = $0 }
        .observing(model.store, { db in try Q.progress(db) }) { progress = $0 }
        .task { await model.feed.enrichMissingDetails() }
    }

    private func makeBox() -> TimeBoxSolver.Box {
        var candidates: [TimeBoxSolver.Candidate] = []
        if useWatchLater {
            candidates += later.map { .init(video: $0.video, reason: "\($0.video.channelTitle) · from Watch later", priority: $0.entry.pinned ? 1.2 : 1) }
        }
        if useSubscriptions {
            let laterIds = Set(later.map(\.video.id))
            candidates += feed.filter { !laterIds.contains($0.id) && (progress[$0.id] ?? 0) < 0.1 }
                .prefix(40)
                .map { .init(video: $0, reason: "\($0.channelTitle) · new", priority: 0.6) }
        }
        return TimeBoxSolver.build(budget: minutes * 60, from: candidates, shuffleSeed: seed)
    }
}

private struct SourceToggle: View {
    var title: String
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            Text(title).font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 10).frame(height: 28)
                .foregroundStyle(isOn ? BX.text : BX.dim)
                .background(isOn ? BX.surface3 : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? .clear : BX.line, style: StrokeStyle(lineWidth: 1, dash: [3])))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct Dial: View {
    @Binding var minutes: Double
    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2 - 12
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let fraction = minutes / 60
            let angle = Angle.degrees(fraction * 360 - 90)
            ZStack {
                Circle().stroke(Color(hex: 0x24242A), lineWidth: 20).padding(12)
                Circle().trim(from: 0, to: min(fraction, 1))
                    .stroke(BX.coral, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(12)
                Circle().fill(.white).frame(width: 30, height: 30)
                    .overlay(Circle().fill(BX.coral).frame(width: 10, height: 10))
                    .position(x: center.x + r * cos(angle.radians), y: center.y + r * sin(angle.radians))
                VStack(spacing: 2) {
                    Text("\(Int(minutes))").font(BX.display(58)).monospacedDigit().contentTransition(.numericText())
                    Text("minutes").font(.system(size: 13, weight: .semibold)).foregroundStyle(BX.muted)
                }
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let dx = v.location.x - center.x, dy = v.location.y - center.y
                var deg = atan2(dy, dx) * 180 / .pi + 90
                if deg < 0 { deg += 360 }
                minutes = max(5, (deg / 360 * 60 / 5).rounded() * 5)
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Time box length")
        .accessibilityValue("\(Int(minutes)) minutes")
        .accessibilityAdjustableAction { d in minutes = max(5, min(60, minutes + (d == .increment ? 5 : -5))) }
    }
}
