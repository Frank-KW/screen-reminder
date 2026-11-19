// Draws the app icon (macOS 27 style, white tile) and writes every size
// into Assets.xcassets/AppIcon.appiconset.
// Run from the repo root:  swift scripts/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
               colors: colors as CFArray, locations: nil)!
}

func draw(_ ctx: CGContext) {
    // Top-left origin, y grows down.
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)

    // Tile: Apple's macOS grid, 824 pt body centered in 1024, continuous corners.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: rgb(0x000000, 0.28))
    ctx.addPath(tilePath)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // White fill with a faint top-to-bottom tint.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xFFFFFF), rgb(0xF1F3F7)]),
                           start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    ctx.restoreGState()

    // Thin edge: bright rim on top, faint gray all round (glass edge).
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.setLineWidth(3)
    ctx.setStrokeColor(rgb(0x000000, 0.06))
    ctx.strokePath()
    let inner = CGPath(roundedRect: tile.insetBy(dx: 4, dy: 4), cornerWidth: 181, cornerHeight: 181, transform: nil)
    ctx.addPath(inner)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 1), rgb(0xFFFFFF, 0)]),
                           start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 400), options: [])
    ctx.restoreGState()

    // --- Bell --- (nudged so bell + badge sit in the optical center)
    ctx.translateBy(x: -32, y: -22)
    let bell = CGMutablePath()
    bell.move(to: CGPoint(x: 262, y: 650))
    bell.addCurve(to: CGPoint(x: 332, y: 520), control1: CGPoint(x: 290, y: 620), control2: CGPoint(x: 332, y: 590))
    bell.addLine(to: CGPoint(x: 332, y: 450))
    bell.addCurve(to: CGPoint(x: 482, y: 300), control1: CGPoint(x: 332, y: 365), control2: CGPoint(x: 398, y: 300))
    bell.addCurve(to: CGPoint(x: 632, y: 450), control1: CGPoint(x: 566, y: 300), control2: CGPoint(x: 632, y: 365))
    bell.addLine(to: CGPoint(x: 632, y: 520))
    bell.addCurve(to: CGPoint(x: 702, y: 650), control1: CGPoint(x: 632, y: 590), control2: CGPoint(x: 674, y: 620))
    bell.addCurve(to: CGPoint(x: 682, y: 690), control1: CGPoint(x: 722, y: 665), control2: CGPoint(x: 712, y: 690))
    bell.addLine(to: CGPoint(x: 282, y: 690))
    bell.addCurve(to: CGPoint(x: 262, y: 650), control1: CGPoint(x: 252, y: 690), control2: CGPoint(x: 242, y: 665))
    bell.closeSubpath()
    bell.addEllipse(in: CGRect(x: 448, y: 252, width: 68, height: 68))      // top knob
    let clapper = CGPath(ellipseIn: CGRect(x: 424, y: 660, width: 116, height: 116), transform: nil)

    let blue = gradient([rgb(0x5AA8FF), rgb(0x1E6BF0), rgb(0x1550C8)])

    // Shadow under the glyph so it floats on the white.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 26, color: rgb(0x1550C8, 0.30))
    ctx.addPath(clapper)
    ctx.addPath(bell)
    ctx.setFillColor(rgb(0x1E6BF0))
    ctx.fillPath()
    ctx.restoreGState()

    for path in [clapper, bell as CGPath] {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(blue, start: CGPoint(x: 0, y: 250), end: CGPoint(x: 0, y: 780), options: [])
        // Glass sheen across the top-left.
        ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.55), rgb(0xFFFFFF, 0)]),
                               startCenter: CGPoint(x: 410, y: 340), startRadius: 0,
                               endCenter: CGPoint(x: 410, y: 340), endRadius: 260, options: [])
        ctx.restoreGState()
    }

    // --- Clock badge ---
    let c = CGPoint(x: 690, y: 668)
    // White ring cuts the badge away from the bell.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 22, color: rgb(0x000000, 0.18))
    ctx.addEllipse(in: CGRect(x: c.x - 152, y: c.y - 152, width: 304, height: 304))
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    let badge = CGPath(ellipseIn: CGRect(x: c.x - 128, y: c.y - 128, width: 256, height: 256), transform: nil)
    ctx.saveGState()
    ctx.addPath(badge)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xFFB340), rgb(0xFF8A00), rgb(0xF26B00)]),
                           start: CGPoint(x: 0, y: c.y - 128), end: CGPoint(x: 0, y: c.y + 128), options: [])
    ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0)]),
                           startCenter: CGPoint(x: c.x - 50, y: c.y - 70), startRadius: 0,
                           endCenter: CGPoint(x: c.x - 50, y: c.y - 70), endRadius: 170, options: [])
    ctx.restoreGState()

    // Hands.
    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.setLineCap(.round)
    ctx.setLineWidth(24)
    ctx.move(to: CGPoint(x: c.x, y: c.y - 78))
    ctx.addLine(to: c)
    ctx.addLine(to: CGPoint(x: c.x + 58, y: c.y + 34))
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.addEllipse(in: CGRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36))
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
}

func render(_ px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / S, y: CGFloat(px) / S)
    draw(ctx)
    return ctx.makeImage()!
}

let dir = URL(fileURLWithPath: "Assets.xcassets/AppIcon.appiconset")
let sizes: [(String, Int)] = [
    ("AppIcon-16.png", 16), ("AppIcon-16@2x.png", 32),
    ("AppIcon-32.png", 32), ("AppIcon-32@2x.png", 64),
    ("AppIcon-128.png", 128), ("AppIcon-128@2x.png", 256),
    ("AppIcon-256.png", 256), ("AppIcon-256@2x.png", 512),
    ("AppIcon-512.png", 512), ("AppIcon-512@2x.png", 1024),
]
for (name, px) in sizes {
    let url = dir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, render(px), nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(name) (\(px)px)")
}
