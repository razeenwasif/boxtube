import SwiftUI

/// The line icons drawn in the mockups (24 × 24 grid, round caps/joins), so the app matches the artboards
/// instead of approximating them with SF Symbols.
public enum BXIcon: String, Sendable {
    case home, shorts, subs, playlists, search, bell, cast, sliders, clock, heart, history, chevronLeft, chevronRight, chevronDown, plus, share, more, moreVertical, camera, music, remix, comment, list, leaf

    @MainActor
    public func view(size: CGFloat = 22, weight: CGFloat = 1.9, fill: Color? = nil) -> some View {
        IconView(icon: self, size: size, lineWidth: weight, fill: fill)
    }
}

public struct IconView: View {
    var icon: BXIcon
    var size: CGFloat
    var lineWidth: CGFloat
    var fill: Color?

    public init(_ icon: BXIcon, size: CGFloat = 22, lineWidth: CGFloat = 1.9, fill: Color? = nil) {
        self.icon = icon; self.size = size; self.lineWidth = lineWidth; self.fill = fill
    }
    init(icon: BXIcon, size: CGFloat, lineWidth: CGFloat, fill: Color?) {
        self.icon = icon; self.size = size; self.lineWidth = lineWidth; self.fill = fill
    }

    public var body: some View {
        ZStack {
            if let fill, let filled = IconPaths.fillPath(icon) {
                filled.fill(fill)
            }
            IconPaths.path(icon)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 24, height: 24)
        .scaleEffect(size / 24)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum IconPaths {
    static func path(_ icon: BXIcon) -> Path {
        var p = Path()
        switch icon {
        case .home:
            // M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z
            p.move(to: .init(x: 3, y: 10.5)); p.addLine(to: .init(x: 12, y: 3)); p.addLine(to: .init(x: 21, y: 10.5))
            p.addLine(to: .init(x: 21, y: 20)); p.addQuadCurve(to: .init(x: 20, y: 21), control: .init(x: 21, y: 21))
            p.addLine(to: .init(x: 15, y: 21)); p.addLine(to: .init(x: 15, y: 15)); p.addLine(to: .init(x: 9, y: 15))
            p.addLine(to: .init(x: 9, y: 21)); p.addLine(to: .init(x: 4, y: 21)); p.addQuadCurve(to: .init(x: 3, y: 20), control: .init(x: 3, y: 21))
            p.closeSubpath()
        case .shorts:
            p.addRoundedRect(in: CGRect(x: 6, y: 2.5, width: 12, height: 19), cornerSize: CGSize(width: 3.5, height: 3.5))
            p.move(to: .init(x: 10.5, y: 9.5)); p.addLine(to: .init(x: 14.5, y: 12)); p.addLine(to: .init(x: 10.5, y: 14.5)); p.closeSubpath()
        case .subs:
            p.addRoundedRect(in: CGRect(x: 3, y: 8, width: 18, height: 13), cornerSize: CGSize(width: 3, height: 3))
            p.move(to: .init(x: 6, y: 4.5)); p.addLine(to: .init(x: 18, y: 4.5))
            p.move(to: .init(x: 10.5, y: 12)); p.addLine(to: .init(x: 14.5, y: 14.5)); p.addLine(to: .init(x: 10.5, y: 17)); p.closeSubpath()
        case .playlists:
            for (y, w) in [(6.0, 12.0), (12, 12), (18, 7)] { p.move(to: .init(x: 3, y: y)); p.addLine(to: .init(x: 3 + w, y: y)) }
            p.move(to: .init(x: 17, y: 18)); p.addLine(to: .init(x: 17, y: 8)); p.addLine(to: .init(x: 21, y: 6.5))
            p.addEllipse(in: CGRect(x: 13, y: 16, width: 4, height: 4))
        case .search:
            p.addEllipse(in: CGRect(x: 4, y: 4, width: 14, height: 14))
            p.move(to: .init(x: 20, y: 20)); p.addLine(to: .init(x: 16.5, y: 16.5))
        case .bell:
            // M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9 ; M10.3 21a1.94 1.94 0 0 0 3.4 0
            p.move(to: .init(x: 6, y: 8)); p.addArc(center: .init(x: 12, y: 8), radius: 6, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addCurve(to: .init(x: 21, y: 17), control1: .init(x: 18, y: 15), control2: .init(x: 21, y: 17))
            p.addLine(to: .init(x: 3, y: 17)); p.addCurve(to: .init(x: 6, y: 8), control1: .init(x: 3, y: 17), control2: .init(x: 6, y: 15))
            p.move(to: .init(x: 10.3, y: 21)); p.addQuadCurve(to: .init(x: 13.7, y: 21), control: .init(x: 12, y: 22.6))
        case .cast:
            p.move(to: .init(x: 2, y: 8)); p.addLine(to: .init(x: 2, y: 6)); p.addQuadCurve(to: .init(x: 4, y: 4), control: .init(x: 2, y: 4))
            p.addLine(to: .init(x: 20, y: 4)); p.addQuadCurve(to: .init(x: 22, y: 6), control: .init(x: 22, y: 4))
            p.addLine(to: .init(x: 22, y: 18)); p.addQuadCurve(to: .init(x: 20, y: 20), control: .init(x: 22, y: 20)); p.addLine(to: .init(x: 14, y: 20))
            p.move(to: .init(x: 2, y: 12)); p.addQuadCurve(to: .init(x: 10, y: 20), control: .init(x: 9.5, y: 12.5))
            p.move(to: .init(x: 2, y: 16)); p.addQuadCurve(to: .init(x: 6, y: 20), control: .init(x: 5.6, y: 16.4))
            p.move(to: .init(x: 2, y: 20)); p.addLine(to: .init(x: 2.01, y: 20))
        case .sliders:
            p.move(to: .init(x: 4, y: 7)); p.addLine(to: .init(x: 13, y: 7)); p.move(to: .init(x: 17, y: 7)); p.addLine(to: .init(x: 20, y: 7))
            p.move(to: .init(x: 4, y: 17)); p.addLine(to: .init(x: 7, y: 17)); p.move(to: .init(x: 11, y: 17)); p.addLine(to: .init(x: 20, y: 17))
            p.addEllipse(in: CGRect(x: 13, y: 5, width: 4, height: 4)); p.addEllipse(in: CGRect(x: 7, y: 15, width: 4, height: 4))
        case .clock:
            p.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            p.move(to: .init(x: 12, y: 7)); p.addLine(to: .init(x: 12, y: 12)); p.addLine(to: .init(x: 15, y: 14))
        case .heart:
            p.move(to: .init(x: 12, y: 21))
            p.addLine(to: .init(x: 4.2, y: 13.4))
            p.addCurve(to: .init(x: 12, y: 5.7), control1: .init(x: 0.6, y: 9.8), control2: .init(x: 6.5, y: 0.5))
            p.addCurve(to: .init(x: 19.8, y: 13.4), control1: .init(x: 17.5, y: 0.5), control2: .init(x: 23.4, y: 9.8))
            p.closeSubpath()
        case .history:
            p.addArc(center: .init(x: 12, y: 12), radius: 9, startAngle: .degrees(180), endAngle: .degrees(225), clockwise: true)
            p.move(to: .init(x: 3, y: 3)); p.addLine(to: .init(x: 3, y: 8)); p.addLine(to: .init(x: 8, y: 8))
            p.move(to: .init(x: 12, y: 7)); p.addLine(to: .init(x: 12, y: 12)); p.addLine(to: .init(x: 15, y: 14))
        case .chevronLeft:
            p.move(to: .init(x: 15, y: 18)); p.addLine(to: .init(x: 9, y: 12)); p.addLine(to: .init(x: 15, y: 6))
        case .chevronRight:
            p.move(to: .init(x: 9, y: 18)); p.addLine(to: .init(x: 15, y: 12)); p.addLine(to: .init(x: 9, y: 6))
        case .chevronDown:
            p.move(to: .init(x: 6, y: 9)); p.addLine(to: .init(x: 12, y: 15)); p.addLine(to: .init(x: 18, y: 9))
        case .plus:
            p.move(to: .init(x: 12, y: 5)); p.addLine(to: .init(x: 12, y: 19)); p.move(to: .init(x: 5, y: 12)); p.addLine(to: .init(x: 19, y: 12))
        case .share:
            p.move(to: .init(x: 4, y: 12)); p.addLine(to: .init(x: 4, y: 19)); p.addQuadCurve(to: .init(x: 6, y: 21), control: .init(x: 4, y: 21))
            p.addLine(to: .init(x: 18, y: 21)); p.addQuadCurve(to: .init(x: 20, y: 19), control: .init(x: 20, y: 21)); p.addLine(to: .init(x: 20, y: 12))
            p.move(to: .init(x: 16, y: 6)); p.addLine(to: .init(x: 12, y: 2)); p.addLine(to: .init(x: 8, y: 6))
            p.move(to: .init(x: 12, y: 2)); p.addLine(to: .init(x: 12, y: 15))
        case .more, .moreVertical:
            break
        case .camera:
            p.move(to: .init(x: 14.5, y: 4)); p.addLine(to: .init(x: 9.5, y: 4)); p.addLine(to: .init(x: 7, y: 7)); p.addLine(to: .init(x: 4, y: 7))
            p.addQuadCurve(to: .init(x: 2, y: 9), control: .init(x: 2, y: 7)); p.addLine(to: .init(x: 2, y: 18))
            p.addQuadCurve(to: .init(x: 4, y: 20), control: .init(x: 2, y: 20)); p.addLine(to: .init(x: 20, y: 20))
            p.addQuadCurve(to: .init(x: 22, y: 18), control: .init(x: 22, y: 20)); p.addLine(to: .init(x: 22, y: 9))
            p.addQuadCurve(to: .init(x: 20, y: 7), control: .init(x: 22, y: 7)); p.addLine(to: .init(x: 17, y: 7)); p.closeSubpath()
            p.addEllipse(in: CGRect(x: 8.5, y: 9.5, width: 7, height: 7))
        case .music:
            p.move(to: .init(x: 9, y: 18)); p.addLine(to: .init(x: 9, y: 5)); p.addLine(to: .init(x: 21, y: 3)); p.addLine(to: .init(x: 21, y: 16))
            p.addEllipse(in: CGRect(x: 3, y: 15, width: 6, height: 6)); p.addEllipse(in: CGRect(x: 15, y: 13, width: 6, height: 6))
        case .remix:
            p.move(to: .init(x: 17, y: 2)); p.addLine(to: .init(x: 21, y: 6)); p.addLine(to: .init(x: 17, y: 10))
            p.move(to: .init(x: 3, y: 11)); p.addLine(to: .init(x: 3, y: 10)); p.addQuadCurve(to: .init(x: 7, y: 6), control: .init(x: 3, y: 6)); p.addLine(to: .init(x: 21, y: 6))
            p.move(to: .init(x: 7, y: 22)); p.addLine(to: .init(x: 3, y: 18)); p.addLine(to: .init(x: 7, y: 14))
            p.move(to: .init(x: 21, y: 13)); p.addLine(to: .init(x: 21, y: 14)); p.addQuadCurve(to: .init(x: 17, y: 18), control: .init(x: 21, y: 18)); p.addLine(to: .init(x: 3, y: 18))
        case .comment:
            p.move(to: .init(x: 21, y: 12))
            p.addArc(center: .init(x: 13, y: 12), radius: 8, startAngle: .degrees(0), endAngle: .degrees(118), clockwise: false)
            p.addLine(to: .init(x: 3, y: 21)); p.addLine(to: .init(x: 4.9, y: 14.6))
            p.addArc(center: .init(x: 13, y: 12), radius: 8, startAngle: .degrees(162), endAngle: .degrees(360), clockwise: false)
        case .list:
            for y in [6.0, 12, 18] { p.move(to: .init(x: 3, y: y)); p.addLine(to: .init(x: y == 18 ? 10 : 15, y: y)) }
        case .leaf:
            p.move(to: .init(x: 11, y: 20)); p.addCurve(to: .init(x: 9.8, y: 6.1), control1: .init(x: 4, y: 20), control2: .init(x: 3, y: 8))
            p.addCurve(to: .init(x: 19, y: 2), control1: .init(x: 15.5, y: 5), control2: .init(x: 17, y: 4.5))
            p.addCurve(to: .init(x: 11, y: 20), control1: .init(x: 22, y: 8), control2: .init(x: 21, y: 20))
            p.move(to: .init(x: 2, y: 21)); p.addCurve(to: .init(x: 7.1, y: 15), control1: .init(x: 2, y: 18), control2: .init(x: 3.9, y: 15.6))
        }
        return p
    }

    static func fillPath(_ icon: BXIcon) -> Path? {
        var p = Path()
        switch icon {
        case .more:
            for x in [5.0, 12, 19] { p.addEllipse(in: CGRect(x: x - 1.6, y: 10.4, width: 3.2, height: 3.2)) }
        case .moreVertical:
            for y in [5.0, 12, 19] { p.addEllipse(in: CGRect(x: 10.4, y: y - 1.6, width: 3.2, height: 3.2)) }
        case .heart:
            return path(icon)
        case .shorts:
            p.move(to: .init(x: 10.5, y: 9.5)); p.addLine(to: .init(x: 14.5, y: 12)); p.addLine(to: .init(x: 10.5, y: 14.5)); p.closeSubpath()
        default:
            return nil
        }
        return p
    }
}

public struct MoreDots: View {
    var vertical: Bool
    var size: CGFloat
    public init(vertical: Bool = false, size: CGFloat = 18) { self.vertical = vertical; self.size = size }
    public var body: some View {
        IconPaths.fillPath(vertical ? .moreVertical : .more)!
            .fill(.foreground)
            .frame(width: 24, height: 24)
            .scaleEffect(size / 24)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
