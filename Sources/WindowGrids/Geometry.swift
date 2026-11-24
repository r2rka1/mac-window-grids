import CoreGraphics

/// Grid maths. Rects are in AppKit coordinates (origin bottom-left, y up) unless stated;
/// the Accessibility API uses the flipped system (origin top-left of the primary screen).
enum Geometry {
    static func rect(span: CellSpan, cols: Int, rows: Int, in frame: CGRect, gap: CGFloat) -> CGRect {
        let cw = frame.width / CGFloat(cols)
        let ch = frame.height / CGFloat(rows)
        let w = cw * CGFloat(span.colSpan)
        let h = ch * CGFloat(span.rowSpan)
        let x = frame.minX + cw * CGFloat(span.col)
        let top = frame.maxY - ch * CGFloat(span.row)
        return CGRect(x: x, y: top - h, width: w, height: h).insetBy(dx: gap / 2, dy: gap / 2)
    }

    static func cell(at p: CGPoint, cols: Int, rows: Int, in frame: CGRect) -> (col: Int, row: Int) {
        let c = Int((p.x - frame.minX) / (frame.width / CGFloat(cols)))
        let r = Int((frame.maxY - p.y) / (frame.height / CGFloat(rows)))
        return (min(max(c, 0), cols - 1), min(max(r, 0), rows - 1))
    }

    static func span(from a: (col: Int, row: Int), to b: (col: Int, row: Int)) -> CellSpan {
        CellSpan(
            col: min(a.col, b.col), row: min(a.row, b.row),
            colSpan: abs(a.col - b.col) + 1, rowSpan: abs(a.row - b.row) + 1)
    }

    /// The span whose edges are closest to the edges of `r`.
    static func nearestSpan(for r: CGRect, cols: Int, rows: Int, in frame: CGRect) -> CellSpan {
        let cw = frame.width / CGFloat(cols)
        let ch = frame.height / CGFloat(rows)
        let c0 = min(max(Int(((r.minX - frame.minX) / cw).rounded()), 0), cols - 1)
        let c1 = min(max(Int(((r.maxX - frame.minX) / cw).rounded()), c0 + 1), cols)
        let r0 = min(max(Int(((frame.maxY - r.maxY) / ch).rounded()), 0), rows - 1)
        let r1 = min(max(Int(((frame.maxY - r.minY) / ch).rounded()), r0 + 1), rows)
        return CellSpan(col: c0, row: r0, colSpan: c1 - c0, rowSpan: r1 - r0)
    }

    /// Converts between AppKit and Accessibility coordinates (the same formula both ways).
    static func flip(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(a.midX - b.midX, a.midY - b.midY) + abs(a.width - b.width) + abs(a.height - b.height)
    }

    static func selfTest() -> Bool {
        var ok = true
        func check(_ cond: Bool, _ what: String) {
            if !cond {
                ok = false
                print("FAIL", what)
            }
        }
        let frame = CGRect(x: 100, y: 50, width: 1600, height: 900)
        let cols = 4
        let rows = 3
        for c in 0..<cols {
            for r in 0..<rows {
                for cs in 1...(cols - c) {
                    for rs in 1...(rows - r) {
                        let s = CellSpan(col: c, row: r, colSpan: cs, rowSpan: rs)
                        let rect = Geometry.rect(span: s, cols: cols, rows: rows, in: frame, gap: 8)
                        check(frame.contains(rect), "rect inside frame \(s)")
                        check(
                            nearestSpan(for: rect, cols: cols, rows: rows, in: frame) == s,
                            "nearestSpan round trip \(s)")
                        let f = flip(rect, primaryHeight: 1000)
                        check(flip(f, primaryHeight: 1000) == rect, "flip involution \(s)")
                    }
                }
                let one = Geometry.rect(
                    span: CellSpan(col: c, row: r), cols: cols, rows: rows, in: frame, gap: 0)
                let hit = cell(at: CGPoint(x: one.midX, y: one.midY), cols: cols, rows: rows, in: frame)
                check(hit.col == c && hit.row == r, "cell at centre \(c),\(r)")
            }
        }
        // Row 0 is the top row: its rect touches the top of the frame.
        let top = Geometry.rect(span: CellSpan(col: 0, row: 0), cols: 2, rows: 2, in: frame, gap: 0)
        check(top.maxY == frame.maxY && top.minX == frame.minX, "row 0 is the top-left")
        // A top-left AppKit rect maps to a small y in Accessibility coordinates.
        check(flip(top, primaryHeight: 1000).minY == 1000 - frame.maxY, "flip puts top at small y")
        let s = span(from: (2, 1), to: (0, 0))
        check(s == CellSpan(col: 0, row: 0, colSpan: 3, rowSpan: 2), "span from two cells")
        return ok
    }
}
