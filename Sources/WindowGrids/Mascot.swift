import AppKit
import SwiftUI

/// The violet pixel-art octopus. Everything branded (app icon, menu bar icon, in-app
/// logo) is drawn from this one 16×16 grid, so it stays crisp at any size.
enum Mascot {
    // v body, l highlight, d shade, w eye white, k pupil, m mouth, . transparent
    static let art: [String] = [
        "................",
        ".....vvvvvv.....",
        "...vvvvvvvvvv...",
        "..vvllvvvvvvvd..",
        ".vvllvvvvvvvvvd.",
        ".vvlvvvvvvvvvvd.",
        ".vvvwwvvvvwwvvd.",
        ".vvvwkvvvvwkvvd.",
        ".vvvvvvvvvvvvvd.",
        ".vvvvvmvvmvvvvd.",
        "..vvvvvmmvvvvd..",
        "..vvvvvvvvvvvd..",
        "..vd.vd..vd.vd..",
        "..vd.vd..vd.vd..",
        ".vd..vd..vd..vd.",
        "vd...vv..vv...vd",
    ]

    static func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static let violet = rgb(0x8B5CF6)
    static var tint: Color { Color(nsColor: violet) }

    private static func color(_ ch: Character, template: Bool) -> NSColor? {
        if template {
            // Silhouette for the menu bar: eyes and mouth are holes.
            return "vldk".contains(ch) ? .black : nil
        }
        switch ch {
        case "v": return violet
        case "l": return rgb(0xC4B5FD)
        case "d": return rgb(0x6D28D9)
        case "k", "m": return rgb(0x2E1065)
        case "w": return .white
        default: return nil
        }
    }

    /// Draws the octopus into `rect` of the current (non-flipped) graphics context.
    static func draw(in rect: CGRect, template: Bool = false) {
        let ctx = NSGraphicsContext.current
        let wasAntialiased = ctx?.shouldAntialias ?? true
        ctx?.shouldAntialias = false  // hard pixel edges
        let p = rect.width / CGFloat(art.count)
        for (y, row) in art.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = color(ch, template: template) else { continue }
                c.setFill()
                CGRect(x: rect.minX + CGFloat(x) * p, y: rect.maxY - CGFloat(y + 1) * p, width: p, height: p)
                    .fill()
            }
        }
        ctx?.shouldAntialias = wasAntialiased
    }

    static func image(size: CGFloat, template: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            draw(in: r, template: template)
            return true
        }
        img.isTemplate = template
        return img
    }

    // MARK: app icons

    enum IconKind { case grids, tracker }

    /// Draws a macOS-style app icon (rounded square with margin) into a square canvas.
    static func drawIcon(_ kind: IconKind, in canvas: CGRect) {
        let box = canvas.insetBy(dx: canvas.width * 0.11, dy: canvas.width * 0.11)
        let u = box.width / 20  // the icon is composed on a 20×20 pixel grid
        func unit(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: box.minX + x * u, y: box.maxY - (y + h) * u, width: w * u, height: h * u)
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225).addClip()
        switch kind {
        case .grids:
            NSGradient(starting: rgb(0x2A2360), ending: rgb(0x14112E))?.draw(in: box, angle: -90)
            // A "half + three rows" layout behind the octopus.
            rgb(0xA78BFA, 0.22).setFill()
            unit(1, 1, 8.5, 18).fill()
            for i in 0..<3 { unit(10.5, 1 + CGFloat(i) * 6.25, 8.5, 5.5).fill() }
            draw(in: unit(2, 2, 16, 16))
        case .tracker:
            NSGradient(starting: rgb(0x241F3D), ending: rgb(0x100E1C))?.draw(in: box, angle: -90)
            // A little activity chart along the bottom.
            let heights: [CGFloat] = [1, 2, 1, 1, 3, 2, 1, 2, 4, 3, 1, 1, 2, 3, 2, 1, 2, 1, 3, 2]
            rgb(0x34D399).setFill()
            for (i, h) in heights.enumerated() { unit(CGFloat(i), 20 - h, 1, h).fill() }
            draw(in: unit(2.5, 1, 15, 15))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    static func writeIcon(_ kind: IconKind, to path: String, pixels: Int = 1024) {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return print("icon failed") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        drawIcon(kind, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
