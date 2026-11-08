import SwiftUI
import Nuke
import NukeUI
import BoxtubeCore

/// Images: a lasting on-disk cache (thumbnails and avatars survive relaunches regardless of HTTP headers).
public enum BoxtubeImages {
    nonisolated(unsafe) private static var configured = false
    public static func configure() {
        guard !configured else { return }
        configured = true
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(name: "com.razeenwasif.boxtube.images", sizeLimit: 400 * 1024 * 1024))
    }
}

// MARK: - Thumbnails

public struct VideoThumbnail: View {
    var video: Video
    var radius: CGFloat
    var showDuration: Bool
    var progress: Double?
    var aspect: CGFloat
    var inset: CGFloat

    public init(_ video: Video, radius: CGFloat = 14, showDuration: Bool = true, progress: Double? = nil, aspect: CGFloat = 16 / 9, inset: CGFloat = 6) {
        self.video = video; self.radius = radius; self.showDuration = showDuration; self.progress = progress; self.aspect = aspect; self.inset = inset
    }

    public var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                ZStack {
                    ArtView(seed: video.id, title: video.title)
                    LazyImage(url: video.bestThumbnail) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .processors([.resize(width: 640)])
                    .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if video.isLive {
                    Badge(text: "LIVE", fill: BX.coral, ink: BX.coralInk).padding(inset)
                } else if showDuration, let text = Format.clock(video.durationSeconds) {
                    Badge(text: text).padding(inset)
                }
            }
            .overlay(alignment: .bottom) {
                if let progress, progress > 0.01 {
                    ProgressLine(value: progress, height: 3)
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous))
                }
            }
            .accessibilityHidden(true)
    }
}

/// Large artwork for hero cards: max-resolution thumbnail, falling back to the regular one, over poster art.
public struct HeroImage: View {
    var video: Video
    public init(video: Video) { self.video = video }
    public var body: some View {
        ZStack {
            ArtView(seed: video.id, title: video.title)
            LazyImage(url: video.bestThumbnail) { state in
                if let image = state.image { image.resizable().aspectRatio(contentMode: .fill) }
            }
            LazyImage(url: video.maxThumbnail) { state in
                if let image = state.image { image.resizable().aspectRatio(contentMode: .fill) }
            }
        }
        .accessibilityHidden(true)
    }
}

public struct Badge: View {
    var text: String
    var fill: Color
    var ink: Color
    public init(text: String, fill: Color = .black.opacity(0.75), ink: Color = .white) {
        self.text = text; self.fill = fill; self.ink = ink
    }
    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(ink)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(fill, in: .rect(cornerRadius: 5))
    }
}

public struct ProgressLine: View {
    var value: Double
    var height: CGFloat
    var tint: Color
    var track: Color
    public init(value: Double, height: CGFloat = 3, tint: Color = BX.coral, track: Color = .white.opacity(0.28)) {
        self.value = value; self.height = height; self.tint = tint; self.track = track
    }
    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                track
                tint.frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Avatars

public struct ChannelAvatar: View {
    var title: String
    var url: URL?
    var size: CGFloat
    public init(title: String, url: URL? = nil, size: CGFloat = 32) {
        self.title = title; self.url = url; self.size = size
    }
    public var body: some View {
        let palette = ArtPalette.forSeed(title)
        ZStack {
            Circle().fill(palette.circle)
            Text(initials).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(palette.bg)
            if let url {
                LazyImage(url: url) { state in
                    if let image = state.image { image.resizable().aspectRatio(contentMode: .fill) }
                }
                .processors([.resize(width: size * 3)])
                .priority(.high)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
    private var initials: String {
        let letters = title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

public struct ProfileAvatar: View {
    var size: CGFloat
    var ring: Color?
    var initials: String
    var photo: URL?
    public init(size: CGFloat = 32, ring: Color? = nil, initials: String = "JD", photo: URL? = nil) {
        self.size = size; self.ring = ring; self.initials = initials; self.photo = photo
    }
    public var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(BX.violet, in: Circle())
            .overlay {
                if let photo {
                    LazyImage(url: photo) { state in
                        if let image = state.image { image.resizable().aspectRatio(contentMode: .fill) }
                    }
                    .processors([.resize(width: size * 3)])
                    .clipShape(Circle())
                }
            }
            .overlay { if let ring { Circle().strokeBorder(ring, lineWidth: 2) } }
            .accessibilityLabel("Your profile")
    }
}

// MARK: - Chips & headers

public struct Chip: View {
    var title: String
    var selected: Bool
    var dot: Color?
    var action: () -> Void
    public init(_ title: String, selected: Bool = false, dot: Color? = nil, action: @escaping () -> Void = {}) {
        self.title = title; self.selected = selected; self.dot = dot; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(title).font(.system(size: 13.5, weight: .semibold))
            }
            .padding(.horizontal, 15)
            .frame(height: 34)
            .foregroundStyle(selected ? BX.ground : BX.text2)
            .background(selected ? BX.text : BX.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

public struct SectionHeader<Trailing: View>: View {
    var title: String
    var icon: String?
    var trailing: Trailing
    public init(_ title: String, icon: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title; self.icon = icon; self.trailing = trailing()
    }
    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).foregroundStyle(BX.coral) }
                Text(title).font(.system(size: 18, weight: .bold)).kerning(-0.2)
            }
            .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing.font(.system(size: 13.5, weight: .semibold)).foregroundStyle(BX.coralText)
        }
    }
}

public struct LargeTitle: View {
    var text: String
    var size: CGFloat
    public init(_ text: String, size: CGFloat = 32) { self.text = text; self.size = size }
    public var body: some View {
        Text(text).font(BX.display(size)).kerning(-size * 0.03).accessibilityAddTraits(.isHeader)
    }
}

public struct CircleIconButton: View {
    var systemName: String
    var label: String
    var size: CGFloat
    var fill: Color
    var tint: Color
    var badge: Bool
    var action: () -> Void
    public init(_ systemName: String, label: String, size: CGFloat = 40, fill: Color = BX.surface2, tint: Color = BX.text, badge: Bool = false, action: @escaping () -> Void) {
        self.systemName = systemName; self.label = label; self.size = size; self.fill = fill; self.tint = tint; self.badge = badge; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(fill, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(BX.coral).frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(fill, lineWidth: 2))
                            .offset(x: -size * 0.2, y: size * 0.2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

public struct BrandMark: View {
    var size: CGFloat
    var fill: Color
    public init(size: CGFloat = 30, fill: Color = BX.coral) { self.size = size; self.fill = fill }
    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(Image(systemName: "play.fill").font(.system(size: size * 0.42)).foregroundStyle(BX.coralInk))
            .accessibilityHidden(true)
    }
}

public struct EqualizerBars: View {
    var color: Color
    var animating: Bool
    public init(color: Color = BX.coral, animating: Bool = true) { self.color = color; self.animating = animating }
    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.15, paused: !animating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 3, height: animating ? 4 + 10 * abs(sin(t * 3 + Double(i) * 1.3)) : [8, 14, 5][i])
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
        .accessibilityLabel("Now playing")
    }
}

/// Segmented scrubber: one segment per chapter, filled up to `position`.
public struct ChapterBar: View {
    var chapters: [Chapter]
    var position: Double
    var duration: Double
    var height: CGFloat
    var tint: Color
    var track: Color
    public init(chapters: [Chapter], position: Double, duration: Double, height: CGFloat = 4, tint: Color = BX.coral, track: Color = .white.opacity(0.25)) {
        self.chapters = chapters; self.position = position; self.duration = duration; self.height = height; self.tint = tint; self.track = track
    }
    public var body: some View {
        GeometryReader { geo in
            let segments = chapters.isEmpty ? [Chapter(index: 0, title: "", start: 0, end: max(duration, 1))] : chapters
            let total = max(duration, segments.last?.end ?? 1)
            let gap: CGFloat = segments.count > 1 ? 3 : 0
            let usable = geo.size.width - gap * CGFloat(segments.count - 1)
            HStack(spacing: gap) {
                ForEach(segments) { c in
                    let fill = c.length > 0 ? min(1, max(0, (position - c.start) / c.length)) : 0
                    let active = position >= c.start && position < c.end
                    ZStack(alignment: .leading) {
                        Capsule().fill(track)
                        Capsule().fill(tint).frame(width: max(0, usable * CGFloat(c.length / total) * fill))
                    }
                    .frame(width: max(2, usable * CGFloat(c.length / total)), height: active && segments.count > 1 ? height * 1.6 : height)
                }
            }
            .frame(height: geo.size.height)
        }
        .frame(height: height * 1.6)
    }
}

public extension Chapter {
    static func current(in chapters: [Chapter], at time: Double) -> Chapter? {
        chapters.last { time >= $0.start }
    }
}
