// Renders the Boxtube app icon (from the design canvas) into the asset catalog.
// Usage: swift scripts/make_icons.swift <AppIcon.appiconset path>
import AppKit
import CoreGraphics

enum Variant { case light, dark, tinted, mac }

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ v: Variant, size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: 0, y: 1024); ctx.scaleBy(x: 1, y: -1) // top-left origin

    let (bg1, bg2, bar, box, tri): (UInt32, UInt32, UInt32, UInt32, UInt32)
    switch v {
    case .light, .mac: (bg1, bg2, bar, box, tri) = (0xFF7262, 0xEC4136, 0x160807, 0x160807, 0xFFF3EA)
    case .dark: (bg1, bg2, bar, box, tri) = (0x26262B, 0x0B0B0D, 0xFF5A4E, 0xFF5A4E, 0x160807)
    case .tinted: (bg1, bg2, bar, box, tri) = (0x1F1F1F, 0x000000, 0xFFFFFF, 0xE8E8E8, 0x000000)
    }

    if v == .mac {
        // 824 pt squircle on the 1024 grid, with a soft drop shadow.
        ctx.translateBy(x: 100, y: 92)
        ctx.scaleBy(x: 0.8047, y: 0.8047)
        ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 40, color: color(0x000000, 0.35))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerWidth: 230, cornerHeight: 230, transform: nil))
        ctx.setFillColor(color(bg2)); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerWidth: 230, cornerHeight: 230, transform: nil))
        ctx.clip()
    }

    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(bg1), color(bg2)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 0), end: CGPoint(x: 512, y: 1024), options: [])

    func rr(_ r: CGRect, _ radius: CGFloat, _ c: CGColor) {
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(c); ctx.fillPath()
    }
    rr(CGRect(x: 332, y: 258, width: 360, height: 38), 19, color(bar, 0.32))
    rr(CGRect(x: 292, y: 312, width: 440, height: 42), 21, color(bar, 0.6))
    rr(CGRect(x: 252, y: 394, width: 520, height: 400), 98, color(0x000000, 0.2))
    rr(CGRect(x: 252, y: 372, width: 520, height: 400), 98, color(box))

    let triangle = CGMutablePath()
    triangle.move(to: CGPoint(x: 460, y: 482)); triangle.addLine(to: CGPoint(x: 460, y: 662)); triangle.addLine(to: CGPoint(x: 620, y: 572)); triangle.closeSubpath()
    ctx.addPath(triangle); ctx.setFillColor(color(tri)); ctx.fillPath()
    ctx.addPath(triangle); ctx.setStrokeColor(color(tri)); ctx.setLineWidth(44); ctx.setLineJoin(.round); ctx.strokePath()

    if v == .mac {
        ctx.resetClip()
        ctx.addPath(CGPath(roundedRect: CGRect(x: 3, y: 3, width: 1018, height: 1018), cornerWidth: 227, cornerHeight: 227, transform: nil))
        ctx.setStrokeColor(color(0xFFFFFF, 0.16)); ctx.setLineWidth(6); ctx.strokePath()
    }

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try render(.light, size: 1024).write(to: out.appending(path: "icon-ios.png"))
try render(.dark, size: 1024).write(to: out.appending(path: "icon-ios-dark.png"))
try render(.tinted, size: 1024).write(to: out.appending(path: "icon-ios-tinted.png"))
for px in [16, 32, 64, 128, 256, 512, 1024] {
    try render(.mac, size: px).write(to: out.appending(path: "icon-mac-\(px).png"))
}
print("icons written to \(out.path)")
