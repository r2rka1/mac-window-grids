import AppKit

/// Draws the grid, the apps already assigned, and the cells under the cursor.
final class OverlayView: NSView {
    var layout: Layout?
    var screenIndex = 0
    var gap: CGFloat = 6
    var selection: CellRange? { didSet { if selection != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        guard let layout else { return }
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        func rect(_ r: CellRange) -> CGRect {
            Geometry.rect(r, in: layout, frame: bounds, gap: gap)
        }
        for cell in layout.cells {
            let path = NSBezierPath(roundedRect: rect(CellRange(cell)), xRadius: 8, yRadius: 8)
            NSColor.white.withAlphaComponent(0.10).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.75).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        var labels: [CellRange: [String]] = [:]
        for a in layout.assignments where a.screen == screenIndex {
            labels[a.range, default: []].append(a.appName)
        }
        for (range, names) in labels {
            let r = rect(range)
            let outline = NSBezierPath(roundedRect: r.insetBy(dx: 5, dy: 5), xRadius: 6, yRadius: 6)
            NSColor.white.withAlphaComponent(0.5).setStroke()
            outline.setLineDash([6, 4], count: 2, phase: 0)
            outline.lineWidth = 1
            outline.stroke()
            let text = NSAttributedString(string: names.joined(separator: " · "), attributes: attrs)
            let size = text.size()
            let pill = CGRect(
                x: r.midX - size.width / 2 - 10, y: r.midY - size.height / 2 - 5,
                width: size.width + 20, height: size.height + 10)
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
            text.draw(at: CGPoint(x: pill.minX + 10, y: pill.minY + 5))
        }

        if let selection {
            let path = NSBezierPath(roundedRect: rect(selection), xRadius: 8, yRadius: 8)
            Mascot.violet.withAlphaComponent(0.5).setFill()
            path.fill()
            Mascot.rgb(0xC4B5FD).setStroke()
            path.lineWidth = 3
            path.stroke()
        }

        let title = NSAttributedString(
            string: layout.name,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ])
        let ts = title.size()
        let tr = CGRect(
            x: bounds.midX - (ts.width + 22) / 2 - 8, y: bounds.maxY - 36, width: ts.width + 22 + 16, height: 24)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: tr, xRadius: 6, yRadius: 6).fill()
        Mascot.draw(in: CGRect(x: tr.minX + 8, y: tr.minY + 4, width: 16, height: 16))
        title.draw(at: CGPoint(x: tr.minX + 30, y: tr.midY - ts.height / 2))
    }
}

/// A click-through window covering one screen's usable area.
final class OverlayWindow: NSWindow {
    let overlay = OverlayView()

    init(screen: NSScreen, index: Int, layout: Layout, gap: CGFloat) {
        super.init(
            contentRect: screen.visibleFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        overlay.layout = layout
        overlay.screenIndex = index
        overlay.gap = gap
        contentView = overlay
        setFrame(screen.visibleFrame, display: false)
    }
}
