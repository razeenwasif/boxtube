import SwiftUI
import CoreGraphics
import ImageIO
import BoxtubeCore

/// Idea 09: derive the window's colors from the current video's thumbnail, on device.
public struct VideoPalette: Hashable, Sendable {
    public var ground: Color
    public var surface: Color
    public var accent: Color
    public var accentInk: Color
    public var muted: Color
    public var swatches: [Color]

    public static let standard = VideoPalette(ground: BX.ground, surface: BX.surface, accent: BX.coral, accentInk: BX.coralInk, muted: BX.muted, swatches: [])

    public static func extract(from url: URL) async -> VideoPalette? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 48] as CFDictionary)
        else { return nil }
        return extract(from: image)
    }

    public static func extract(from image: CGImage) -> VideoPalette? {
        let size = 24
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        struct HSB { var h, s, b: Double }
        var samples: [HSB] = []
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b), d = maxC - minC
            var h = 0.0
            if d > 0 {
                if maxC == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
                else if maxC == g { h = (b - r) / d + 2 }
                else { h = (r - g) / d + 4 }
                h /= 6; if h < 0 { h += 1 }
            }
            samples.append(HSB(h: h, s: maxC == 0 ? 0 : d / maxC, b: maxC))
        }
        // Accent: the most vivid bright colour. Ground: hue of the dominant mid-dark area.
        let accentSample = samples.max { ($0.s * 0.7 + $0.b * 0.3) < ($1.s * 0.7 + $1.b * 0.3) } ?? HSB(h: 0.02, s: 0.7, b: 1)
        var buckets = [Int](repeating: 0, count: 12)
        for s in samples where s.s > 0.15 { buckets[min(11, Int(s.h * 12))] += 1 }
        let dominantHue = (Double(buckets.firstIndex(of: buckets.max() ?? 0) ?? 0) + 0.5) / 12
        let groundHue = buckets.max() ?? 0 > 20 ? dominantHue : accentSample.h

        let ground = Color(hue: groundHue, saturation: 0.55, brightness: 0.1)
        let surface = Color(hue: groundHue, saturation: 0.5, brightness: 0.17)
        let accent = Color(hue: accentSample.h, saturation: min(0.75, max(0.25, accentSample.s)), brightness: max(0.85, accentSample.b))
        let muted = Color(hue: groundHue, saturation: 0.18, brightness: 0.78)
        let swatches = [accent, Color(hue: dominantHue, saturation: 0.6, brightness: 0.6), surface]
        return VideoPalette(ground: ground, surface: surface, accent: accent, accentInk: Color(hue: groundHue, saturation: 0.6, brightness: 0.12), muted: muted, swatches: swatches)
    }
}
