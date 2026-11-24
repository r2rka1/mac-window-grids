import CoreGraphics
import Foundation

/// Grid maths. Screen rects are in AppKit coordinates (origin bottom-left, y up) unless
/// stated; the Accessibility API uses the flipped system (origin top-left of the
/// primary screen). "Unit" rects are fractions 0…1 of the screen with a top-left origin.
enum Geometry {
    static func unitRect(_ cell: Cell, in layout: Layout) -> CGRect {
        let total = layout.columns.reduce(0) { $0 + $1.weight }
        let before = layout.columns.prefix(cell.col).reduce(0) { $0 + $1.weight }
        let column = layout.columns[cell.col]
        let h = 1 / CGFloat(column.rows)
        return CGRect(
            x: CGFloat(before / total), y: CGFloat(cell.row) * h,
            width: CGFloat(column.weight / total), height: h)
    }

    static func unitRect(_ range: CellRange, in layout: Layout) -> CGRect {
        unitRect(range.a, in: layout).union(unitRect(range.b, in: layout))
    }

    static func rect(_ range: CellRange, in layout: Layout, frame: CGRect, gap: CGFloat) -> CGRect {
        let u = unitRect(range, in: layout)
        return CGRect(
            x: frame.minX + u.minX * frame.width, y: frame.maxY - u.maxY * frame.height,
            width: u.width * frame.width, height: u.height * frame.height
        ).insetBy(dx: gap / 2, dy: gap / 2)
    }

    static func cell(at p: CGPoint, in layout: Layout, frame: CGRect) -> Cell {
        let fx = min(max((p.x - frame.minX) / frame.width, 0), 0.999_999)
        let fy = min(max((frame.maxY - p.y) / frame.height, 0), 0.999_999)
        var col = layout.columns.count - 1
        for c in layout.columns.indices where fx < unitRect(Cell(col: c, row: 0), in: layout).maxX {
            col = c
            break
        }
        let rows = layout.columns[col].rows
        return Cell(col: col, row: min(Int(fy * CGFloat(rows)), rows - 1))
    }

    /// The range whose rectangle is closest to `r`; among equals, the first found.
    static func nearestRange(for r: CGRect, in layout: Layout, frame: CGRect) -> CellRange {
        let cells = layout.cells
        var best = CellRange(cells[0])
        var bestDistance = CGFloat.infinity
        for (i, a) in cells.enumerated() {
            for b in cells[i...] {
                let range = CellRange(a, b)
                let c = rect(range, in: layout, frame: frame, gap: 0)
                let d = abs(c.minX - r.minX) + abs(c.maxX - r.maxX) + abs(c.minY - r.minY) + abs(c.maxY - r.maxY)
                if d < bestDistance - 0.5 {
                    bestDistance = d
                    best = range
                }
            }
        }
        return best
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
        func close(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01 && abs(a.width - b.width) < 0.01
                && abs(a.height - b.height) < 0.01
        }
        let frame = CGRect(x: 100, y: 50, width: 1600, height: 900)

        // The case from the request: left half, right half split into 3 rows.
        let half = Layout(name: "t", rows: [1, 3])
        let left = rect(CellRange(Cell(col: 0, row: 0)), in: half, frame: frame, gap: 0)
        check(close(left, CGRect(x: 100, y: 50, width: 800, height: 900)), "left half is full height")
        let mid = rect(CellRange(Cell(col: 1, row: 1)), in: half, frame: frame, gap: 0)
        check(close(mid, CGRect(x: 900, y: 350, width: 800, height: 300)), "right middle third")
        let topRight = rect(CellRange(Cell(col: 1, row: 0)), in: half, frame: frame, gap: 0)
        check(abs(topRight.maxY - frame.maxY) < 0.01, "row 0 is the top row")
        check(abs(flip(topRight, primaryHeight: 1000).minY - 50) < 0.01, "flip puts the top at small y")

        // Uneven widths and row counts.
        let l = Layout(
            name: "t",
            columns: [Column(weight: 1, rows: 1), Column(weight: 1, rows: 3), Column(weight: 2, rows: 2)])
        let wide = rect(CellRange(Cell(col: 2, row: 0)), in: l, frame: frame, gap: 0)
        check(abs(wide.width - 800) < 0.01 && abs(wide.minX - 900) < 0.01, "weighted column width")
        for a in l.cells {
            let one = rect(CellRange(a), in: l, frame: frame, gap: 8)
            check(frame.contains(one), "cell inside frame \(a)")
            check(cell(at: CGPoint(x: one.midX, y: one.midY), in: l, frame: frame) == a, "cell at centre \(a)")
            check(close(flip(flip(one, primaryHeight: 1000), primaryHeight: 1000), one), "flip involution")
            for b in l.cells {
                let range = CellRange(a, b)
                let r = rect(range, in: l, frame: frame, gap: 0)
                let back = rect(nearestRange(for: r, in: l, frame: frame), in: l, frame: frame, gap: 0)
                check(close(back, r), "nearestRange round trip \(a) \(b)")
            }
        }
        check(CellRange(Cell(col: 2, row: 1), Cell(col: 0, row: 0)).a == Cell(col: 0, row: 0), "range is ordered")
        check(cell(at: CGPoint(x: -50, y: 5000), in: l, frame: frame) == Cell(col: 0, row: 0), "clamps outside points")

        // Files written by the first version still load.
        let old = """
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old","cols":3,"rows":2,"assignments":[
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964F0","bundleID":"x.y","appName":"Y","screen":0,
             "span":{"col":0,"row":0,"colSpan":2,"rowSpan":2}}]}
            """
        if let m = try? JSONDecoder().decode(Layout.self, from: Data(old.utf8)) {
            check(m.columns == Array(repeating: Column(rows: 2), count: 3), "legacy grid migrates")
            check(
                m.assignments.first?.range == CellRange(Cell(col: 0, row: 0), Cell(col: 1, row: 1)),
                "legacy span migrates")
            check(m.sanitized().assignments.count == 1, "migrated assignment survives sanitising")
        } else {
            check(false, "legacy layout decodes")
        }
        if let data = try? JSONEncoder().encode(l), let again = try? JSONDecoder().decode(Layout.self, from: data) {
            check(again == l, "current format round trips")
        } else {
            check(false, "current layout encodes and decodes")
        }
        let shrunk = Layout(
            name: "t", rows: [1, 1],
            assignments: [Assignment(bundleID: "a", appName: "A", range: CellRange(Cell(col: 1, row: 2)))])
        check(shrunk.sanitized().assignments.isEmpty, "assignment to a removed row is dropped")
        return ok
    }
}
