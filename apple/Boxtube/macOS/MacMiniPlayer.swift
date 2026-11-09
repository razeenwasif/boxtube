import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

/// The video you were watching, snapped to a corner of the window after you go back
/// (the "Snapped to corner" player on the Keyboard first artboard). Drag it to another corner.
struct MacMiniPlayer: View {
    @Environment(AppModel.self) private var model
    @State private var corner = Corner.bottomTrailing
    @State private var drag: CGSize = .zero
    @State private var hovering = false

    enum Corner {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        var alignment: Alignment {
            switch self {
            case .topLeading: .topLeading
            case .topTrailing: .topTrailing
            case .bottomLeading: .bottomLeading
            case .bottomTrailing: .bottomTrailing
            }
        }
        var isTop: Bool { self == .topLeading || self == .topTrailing }
        var isLeading: Bool { self == .topLeading || self == .bottomLeading }
    }

    static let size = CGSize(width: 360, height: 203)

    var body: some View {
        GeometryReader { geo in
            if let video = model.player.video {
                card(video)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .offset(drag)
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { drag = $0.translation }
                            .onEnded { g in snap(g.translation, in: geo.size) }
                    )
                    .padding(.top, corner.isTop ? 84 : 24)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
                    .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
    }

    private func card(_ video: Video) -> some View {
        let s = model.player.state
        let showControls = hovering || !s.isPlaying
        return ZStack {
            PlayerSurface(engine: model.player, interactive: false)
                .allowsHitTesting(false)
            if showControls {
                LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(video.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                            Text(video.channelTitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        iconButton("arrow.up.left.and.arrow.down.right", "Back to the video", filled: true) { expand() }
                        iconButton("xmark", "Close", filled: true) { close() }
                    }
                    Spacer()
                    HStack(spacing: 22) {
                        iconButton("gobackward.10", "Back 10 seconds", size: 17) { model.player.skip(-10) }
                        iconButton(s.isPlaying ? "pause.fill" : "play.fill", s.isPlaying ? "Pause" : "Play", size: 24) { model.player.toggle() }
                        iconButton("goforward.10", "Forward 10 seconds", size: 17) { model.player.skip(10) }
                    }
                    Spacer()
                    HStack {
                        Text("\(Format.clock(s.time)) / \(Format.clock(s.duration))").font(.system(size: 11, weight: .semibold).monospacedDigit())
                        Spacer()
                    }
                }
                .foregroundStyle(.white)
                .padding(10)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) { ProgressLine(value: s.progress, height: 3).allowsHitTesting(false) }
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.5), radius: 25, y: 20)
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture { expand() }
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .help("Click to go back to the video, drag to move")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mini player: \(video.title)")
    }

    private func iconButton(_ name: String, _ label: String, size: CGFloat = 13, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: size, weight: .bold))
                .frame(width: max(28, size + 12), height: max(28, size + 12))
                .background(filled ? Color.black.opacity(0.35) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func expand() {
        guard let video = model.player.video else { return }
        model.watching = video
    }

    private func close() {
        withAnimation(.snappy) { model.player.stop() }
    }

    /// Snap to whichever corner the card was dropped nearest.
    private func snap(_ t: CGSize, in area: CGSize) {
        let w = Self.size.width, h = Self.size.height
        let startX = corner.isLeading ? 24 + w / 2 : area.width - 24 - w / 2
        let startY = corner.isTop ? 84 + h / 2 : area.height - 24 - h / 2
        let x = startX + t.width, y = startY + t.height
        let next: Corner = y < area.height / 2
            ? (x < area.width / 2 ? .topLeading : .topTrailing)
            : (x < area.width / 2 ? .bottomLeading : .bottomTrailing)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            corner = next
            drag = .zero
        }
    }
}
