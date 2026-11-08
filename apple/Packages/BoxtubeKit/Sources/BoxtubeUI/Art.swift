import SwiftUI
import BoxtubeCore

/// The poster-style artwork from the mockups (solid field, circle, big word). Used as the placeholder
/// behind every real thumbnail and as cover art for playlists and chapters.
public struct ArtPalette: Hashable, Sendable {
    public var bg: Color
    public var circle: Color
    public var ink: Color

    public static let all: [ArtPalette] = [
        .init(bg: Color(hex: 0x1B2A4A), circle: Color(hex: 0xFF6B57), ink: Color(hex: 0xF5F1E6)),
        .init(bg: Color(hex: 0x3B1F4A), circle: Color(hex: 0xF7B267), ink: Color(hex: 0xFCE9D9)),
        .init(bg: Color(hex: 0xE9E2D0), circle: Color(hex: 0x2F5D50), ink: Color(hex: 0x1A1A1A)),
        .init(bg: Color(hex: 0x0F3D3A), circle: Color(hex: 0xE8F27A), ink: Color(hex: 0xF1F5F0)),
        .init(bg: Color(hex: 0xC4442F), circle: Color(hex: 0xF3D9B1), ink: Color(hex: 0xFFF6EA)),
        .init(bg: Color(hex: 0xE8C07D), circle: Color(hex: 0x7A3B1E), ink: Color(hex: 0x2A160C)),
        .init(bg: Color(hex: 0x141416), circle: Color(hex: 0xFF5A4E), ink: .white),
        .init(bg: Color(hex: 0x2E3B2A), circle: Color(hex: 0xD9C9A3), ink: Color(hex: 0xF2EEE3)),
        .init(bg: Color(hex: 0x0E1F3A), circle: Color(hex: 0x3D6FD8), ink: Color(hex: 0xEAF0FF)),
        .init(bg: Color(hex: 0x26213F), circle: Color(hex: 0x8C6BD1), ink: Color(hex: 0xF0EAFF)),
    ]

    public static func forSeed(_ seed: String) -> ArtPalette {
        all[Int(stableHash(seed) % UInt64(all.count))]
    }

    public static func stableHash(_ seed: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return hash
    }
}

public enum ArtWord {
    public static func from(_ title: String) -> String {
        let words = title.uppercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 && !["THE", "AND", "FOR", "WITH", "HOW", "WHY", "YOU", "YOUR", "THIS", "THAT", "FROM"].contains($0) }
        let best = words.first { $0.count <= 7 } ?? words.first.map { String($0.prefix(6)) } ?? "BOX"
        return best
    }
}

public struct ArtView: View {
    var seed: String
    var word: String
    var palette: ArtPalette
    var showWord: Bool

    public init(seed: String, title: String, word: String? = nil, palette: ArtPalette? = nil, showWord: Bool = true) {
        self.seed = seed
        self.word = word ?? ArtWord.from(title)
        self.palette = palette ?? .forSeed(seed)
        self.showWord = showWord
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let variant = Int((ArtPalette.stableHash(seed) >> 8) % 3)
            let size = [w * 0.58, w * 0.46, w * 0.7][variant]
            let offset = [CGPoint(x: w - size * 0.8, y: -size * 0.25), CGPoint(x: w - size - w * 0.08, y: h * 0.1), CGPoint(x: w - size * 0.75, y: -size * 0.35)][variant]
            ZStack(alignment: .bottomLeading) {
                palette.bg
                Circle().fill(palette.circle)
                    .frame(width: size, height: size)
                    .position(x: offset.x + size / 2, y: offset.y + size / 2)
                if showWord {
                    Text(word)
                        .font(BX.display(min(w * 0.16, h * 0.42)))
                        .kerning(-w * 0.004)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.leading, w * 0.07)
                        .padding(.bottom, h * 0.1)
                        .padding(.trailing, w * 0.05)
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
    }
}
