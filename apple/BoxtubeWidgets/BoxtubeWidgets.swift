import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
import BoxtubeCore

@main
struct BoxtubeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlaybackLiveActivity()
        TimeBoxWidget()
    }
}

private let coral = Color(red: 1, green: 0.353, blue: 0.306)
private let coralInk = Color(red: 0.086, green: 0.031, blue: 0.027)

// MARK: - Live Activity + Dynamic Island (idea 05)

struct PlaybackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "boxtube://watch?v=\(context.attributes.videoId)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Thumb(videoId: context.attributes.videoId).frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 13))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title).font(.system(size: 14.5, weight: .bold)).lineLimit(1)
                        Text(chapterLine(context.state)).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ProgressRing(progress: chapterProgress(context.state)).frame(width: 34, height: 34)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        Segments(state: context.state, tint: coral, track: Color.white.opacity(0.18))
                        Controls(isPlaying: context.state.isPlaying)
                    }
                }
            } compactLeading: {
                Thumb(videoId: context.attributes.videoId).frame(width: 24, height: 24).clipShape(.rect(cornerRadius: 7))
            } compactTrailing: {
                ProgressRing(progress: context.state.progress).frame(width: 20, height: 20)
            } minimal: {
                ProgressRing(progress: context.state.progress).frame(width: 20, height: 20)
            }
            .widgetURL(URL(string: "boxtube://watch?v=\(context.attributes.videoId)"))
            .keylineTint(coral)
        }
    }
}

private func chapterLine(_ s: PlaybackActivityAttributes.ContentState) -> String {
    if let i = s.chapterIndex, let t = s.chapterTitle { return "Chapter \(i + 1) · \(t)" }
    return s.isPlaying ? "Playing" : "Paused"
}

private func chapterProgress(_ s: PlaybackActivityAttributes.ContentState) -> Double {
    guard let i = s.chapterIndex, s.chapterStarts.indices.contains(i) else { return s.progress }
    let start = s.chapterStarts[i]
    let end = i + 1 < s.chapterStarts.count ? s.chapterStarts[i + 1] : s.duration
    return end > start ? min(1, max(0, (s.position - start) / (end - start))) : 0
}

private func clock(_ t: Double) -> String {
    let s = Int(max(0, t))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

struct LockScreenView: View {
    let context: ActivityViewContext<PlaybackActivityAttributes>
    var body: some View {
        let s = context.state
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Thumb(videoId: context.attributes.videoId).frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5).fill(coral).frame(width: 16, height: 16)
                            .overlay(Image(systemName: "play.fill").font(.system(size: 7)).foregroundStyle(coralInk))
                        Text(s.chapterCount > 0 ? "BOXTUBE · CHAPTER \((s.chapterIndex ?? 0) + 1) OF \(s.chapterCount)" : "BOXTUBE")
                            .font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(red: 1, green: 0.54, blue: 0.5))
                    }
                    Text(context.attributes.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text([s.chapterTitle, context.attributes.channel].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Segments(state: s, tint: .white, track: .white.opacity(0.3))
            HStack {
                Text(clock(s.position)).frame(width: 64, alignment: .leading)
                Spacer()
                Controls(isPlaying: s.isPlaying, light: true)
                Spacer()
                Text("−" + clock(s.remaining)).frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.white.opacity(0.72))
        }
        .padding(14)
        .foregroundStyle(.white)
    }
}

struct Segments: View {
    var state: PlaybackActivityAttributes.ContentState
    var tint: Color
    var track: Color
    var body: some View {
        GeometryReader { geo in
            let starts = state.chapterStarts.isEmpty ? [0] : state.chapterStarts
            let total = max(state.duration, 1)
            let gap: CGFloat = starts.count > 1 ? 3 : 0
            let usable = geo.size.width - gap * CGFloat(starts.count - 1)
            HStack(spacing: gap) {
                ForEach(Array(starts.enumerated()), id: \.offset) { i, start in
                    let end = i + 1 < starts.count ? starts[i + 1] : total
                    let fill = end > start ? min(1, max(0, (state.position - start) / (end - start))) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(track)
                        Capsule().fill(tint).frame(width: usable * CGFloat((end - start) / total) * fill)
                    }
                    .frame(width: max(2, usable * CGFloat((end - start) / total)))
                }
            }
        }
        .frame(height: 4)
    }
}

struct Controls: View {
    var isPlaying: Bool
    var light = false
    var body: some View {
        HStack(spacing: 22) {
            Button(intent: SkipBackIntent()) { Text("−10").font(.system(size: 13, weight: .bold)) }
                .buttonStyle(.plain)
            Button(intent: TogglePlaybackIntent()) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18))
                    .foregroundStyle(light ? .black : .white)
                    .frame(width: 44, height: 44)
                    .background(light ? Color.white : Color.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            Button(intent: SkipForwardIntent()) { Text("+10").font(.system(size: 13, weight: .bold)) }
                .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }
}

struct ProgressRing: View {
    var progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 4)
            Circle().trim(from: 0, to: progress).stroke(coral, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .padding(2)
    }
}

/// Thumbnails can't be fetched inside a Live Activity, so it shows the poster art in the video's colours.
struct Thumb: View {
    var videoId: String
    var body: some View {
        let palettes: [(Color, Color)] = [
            (Color(red: 0.106, green: 0.165, blue: 0.29), Color(red: 1, green: 0.42, blue: 0.34)),
            (Color(red: 0.23, green: 0.12, blue: 0.29), Color(red: 0.97, green: 0.7, blue: 0.4)),
            (Color(red: 0.06, green: 0.24, blue: 0.23), Color(red: 0.91, green: 0.95, blue: 0.48)),
            (Color(red: 0.77, green: 0.27, blue: 0.18), Color(red: 0.95, green: 0.85, blue: 0.69)),
        ]
        let p = palettes[abs(videoId.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palettes.count]
        GeometryReader { g in
            ZStack {
                p.0
                Circle().fill(p.1).frame(width: g.size.width * 0.7).offset(x: g.size.width * 0.25, y: -g.size.height * 0.25)
            }
        }
    }
}

// MARK: - Lock screen / home widget: start a time box

struct TimeBoxWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TimeBox", provider: TimeBoxProvider()) { _ in
            TimeBoxWidgetView()
                .containerBackground(for: .widget) { Color(red: 0.07, green: 0.07, blue: 0.08) }
                .widgetURL(URL(string: "boxtube://timebox"))
        }
        .configurationDisplayName("Time box")
        .description("Build a box of videos that fits the time you have.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .systemSmall])
    }
}

struct TimeBoxEntry: TimelineEntry { let date: Date }

struct TimeBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimeBoxEntry { TimeBoxEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (TimeBoxEntry) -> Void) { completion(TimeBoxEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TimeBoxEntry>) -> Void) {
        completion(Timeline(entries: [TimeBoxEntry(date: .now)], policy: .never))
    }
}

struct TimeBoxWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("25").font(.system(size: 17, weight: .heavy))
                    Text("MIN").font(.system(size: 8, weight: .bold))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("TIME BOX").font(.system(size: 10.5, weight: .heavy))
                Text("25 min ready").font(.system(size: 15, weight: .bold))
                Text("Tap to fill it").font(.system(size: 11.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 9).fill(coral).frame(width: 30, height: 30)
                    .overlay(Image(systemName: "timer").font(.system(size: 14, weight: .bold)).foregroundStyle(coralInk))
                Spacer()
                Text("Time box").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Text("Fill the time you have").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
