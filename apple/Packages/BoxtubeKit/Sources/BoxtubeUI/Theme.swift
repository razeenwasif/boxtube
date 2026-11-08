import SwiftUI
import CoreText

/// Design tokens from the redesign canvas.
public enum BX {
    public static let ground = Color(hex: 0x0B0B0D)
    public static let surface = Color(hex: 0x141417)
    public static let surface2 = Color(hex: 0x1A1A1E)
    public static let surface3 = Color(hex: 0x222227)
    public static let line = Color.white.opacity(0.08)
    public static let text = Color(hex: 0xF4F4F5)
    public static let text2 = Color(hex: 0xD4D4D8)
    public static let muted = Color(hex: 0xA1A1AA)
    public static let dim = Color(hex: 0x8A8A93)
    public static let coral = Color(hex: 0xFF5A4E)
    public static let coralText = Color(hex: 0xFF8A80)
    public static let coralInk = Color(hex: 0x160807)
    public static let cream = Color(hex: 0xFFF3EA)
    public static let amber = Color(hex: 0xF7B267)
    public static let teal = Color(hex: 0x5CC8B4)
    public static let sage = Color(hex: 0x9DB39A)
    public static let sageText = Color(hex: 0xC2D4BF)
    public static let violet = Color(hex: 0x7C5CFF)
    public static let calmGround = Color(hex: 0x0E0F0E)

    public static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        BoxtubeFonts.registered ? .custom("Bricolage Grotesque", size: size).weight(weight) : .system(size: size, weight: weight, design: .rounded)
    }
}

public enum BoxtubeFonts {
    nonisolated(unsafe) public private(set) static var registered = false

    /// Registers the bundled Bricolage Grotesque (SIL OFL) display face once at launch.
    public static func register() {
        guard !registered, let url = Bundle.module.url(forResource: "BricolageGrotesque", withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: "BricolageGrotesque", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        registered = true
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Glass

public extension View {
    /// Liquid Glass surface used by the island, mini player, control bars and panels.
    func boxGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return self.glassEffect(glass, in: shape)
    }

    func boxCard(_ radius: CGFloat = 18, fill: Color = BX.surface) -> some View {
        background(fill, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(BX.line))
    }
}
