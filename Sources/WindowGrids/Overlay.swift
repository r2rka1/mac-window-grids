import AppKit

/// Draws the grid, the apps already assigned, and the cells under the cursor.
final class OverlayView: NSView {
    var layout: Layout?
    var screenIndex = 0
    var gap: CGFloat = 6
    var selection: CellSpan? { didSet { if selection != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        guard let layout else { return }
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        func rect(_ s: CellSpan) -> CGRect {
            Geometry.rect(span: s, cols: layout.cols, rows: layout.rows, in: bounds, gap: gap)
        }
        for c in 0..<layout.cols {
            for r in 0..<layout.rows {
                let path = NSBezierPath(roundedRect: rect(CellSpan(col: c, row: r)), xRadius: 8, yRadius: 8)
                NSColor.white.withAlphaComponent(0.10).setFill()
                path.fill()
                NSColor.white.withAlphaComponent(0.75).setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        var labels: [CellSpan: [String]] = [:]
        for a in layout.assignments where a.screen == screenIndex {
            labels[a.span, default: []].append(a.appName)
        }
        for (span, names) in labels {
            let r = rect(span)
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
            NSColor.controlAccentColor.withAlphaComponent(0.45).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 3
            path.stroke()
        }

        let title = NSAttributedString(
            string: "\(layout.name)  ·  \(layout.cols)×\(layout.rows)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ])
        let ts = title.size()
        let tr = CGRect(x: bounds.midX - ts.width / 2 - 8, y: bounds.maxY - ts.height - 14, width: ts.width + 16, height: ts.height + 6)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: tr, xRadius: 6, yRadius: 6).fill()
        title.draw(at: CGPoint(x: tr.minX + 8, y: tr.minY + 3))
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
