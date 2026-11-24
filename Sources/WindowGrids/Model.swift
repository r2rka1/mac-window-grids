import Foundation

/// A grid is a row of columns; each column has its own width and its own number of rows.
struct Column: Codable, Hashable {
    /// Relative width: a column of weight 2 is twice as wide as one of weight 1.
    var weight: Double = 1
    var rows: Int = 1
}

/// One cell. Row 0 is the top row of its column.
struct Cell: Codable, Hashable {
    var col: Int
    var row: Int
}

/// The rectangle covering two cells (and everything between them). A single cell is
/// a range from the cell to itself.
struct CellRange: Codable, Hashable {
    var a: Cell
    var b: Cell

    init(_ a: Cell, _ b: Cell) {
        let swap = a.col > b.col || (a.col == b.col && a.row > b.row)
        self.a = swap ? b : a
        self.b = swap ? a : b
    }

    init(_ cell: Cell) { self.init(cell, cell) }
}

/// One app window placed in a layout.
struct Assignment: Codable, Identifiable, Hashable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var range: CellRange
    var screen: Int = 0
}

struct Layout: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var columns: [Column]
    var assignments: [Assignment] = []

    static let maxColumns = 8
    static let maxRows = 8

    init(name: String, columns: [Column], assignments: [Assignment] = []) {
        self.name = name
        self.columns = columns
        self.assignments = assignments
    }

    /// `rows[i]` is the number of rows in column i; all columns equally wide.
    init(name: String, rows: [Int], assignments: [Assignment] = []) {
        self.init(name: name, columns: rows.map { Column(rows: $0) }, assignments: assignments)
    }

    var cells: [Cell] {
        columns.enumerated().flatMap { c, column in (0..<column.rows).map { Cell(col: c, row: $0) } }
    }

    var summary: String { columns.map { String($0.rows) }.joined(separator: "·") }

    func contains(_ cell: Cell) -> Bool {
        columns.indices.contains(cell.col) && (0..<columns[cell.col].rows).contains(cell.row)
    }

    /// Clamps the grid to sane limits and drops assignments whose cells no longer exist.
    func sanitized() -> Layout {
        var l = self
        if l.columns.isEmpty { l.columns = [Column()] }
        l.columns = l.columns.prefix(Self.maxColumns).map {
            Column(weight: min(max($0.weight, 0.25), 4), rows: min(max($0.rows, 1), Self.maxRows))
        }
        l.assignments = assignments.filter { l.contains($0.range.a) && l.contains($0.range.b) }
        return l
    }
}

// Decoding also accepts the first file format, which had a uniform cols × rows grid
// and assignments stored as col/row/colSpan/rowSpan.
extension Layout {
    private enum LegacyKeys: String, CodingKey { case cols, rows }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        assignments = try c.decodeIfPresent([Assignment].self, forKey: .assignments) ?? []
        if let cols = try c.decodeIfPresent([Column].self, forKey: .columns) {
            columns = cols
        } else {
            let old = try decoder.container(keyedBy: LegacyKeys.self)
            let cols = try old.decode(Int.self, forKey: .cols)
            let rows = try old.decode(Int.self, forKey: .rows)
            columns = Array(repeating: Column(rows: rows), count: max(cols, 1))
        }
    }
}

extension Assignment {
    private enum LegacyKeys: String, CodingKey { case span }
    private struct LegacySpan: Codable {
        var col: Int
        var row: Int
        var colSpan: Int
        var rowSpan: Int
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        appName = try c.decode(String.self, forKey: .appName)
        screen = try c.decodeIfPresent(Int.self, forKey: .screen) ?? 0
        if let r = try c.decodeIfPresent(CellRange.self, forKey: .range) {
            range = r
        } else {
            let s = try decoder.container(keyedBy: LegacyKeys.self).decode(LegacySpan.self, forKey: .span)
            range = CellRange(
                Cell(col: s.col, row: s.row),
                Cell(col: s.col + s.colSpan - 1, row: s.row + s.rowSpan - 1))
        }
    }
}

struct Settings: Codable, Equatable {
    var gap: Double = 6
    var hideOthers = false
    var launchMissing = true
    var hotkeys = true
}

private struct Persisted: Codable {
    var layouts: [Layout]
    var activeID: UUID?
    var settings: Settings
}

final class Store: ObservableObject {
    @Published var layouts: [Layout] = [] { didSet { save() } }
    @Published var activeID: UUID? { didSet { save() } }
    @Published var settings = Settings() { didSet { save() } }

    private let url: URL?

    /// `persist: false` keeps everything in memory (used for rendering screenshots).
    init(persist: Bool = true) {
        if persist {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WindowGrids")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent("layouts.json")
        } else {
            url = nil
        }
        if let url, let data = try? Data(contentsOf: url),
            let p = try? JSONDecoder().decode(Persisted.self, from: data)
        {
            layouts = p.layouts.map { $0.sanitized() }
            activeID = p.activeID
            settings = p.settings
        } else {
            if let url, FileManager.default.fileExists(atPath: url.path) {
                // Unreadable file: keep it aside rather than overwrite it with defaults.
                try? FileManager.default.copyItem(at: url, to: url.appendingPathExtension("bak"))
            }
            layouts = [
                Layout(name: "Halves", rows: [1, 1]),
                Layout(name: "Half + stack", rows: [1, 3]),
                Layout(name: "Quarters", rows: [2, 2]),
            ]
            activeID = layouts[0].id
            save()
        }
    }

    var active: Layout? { layouts.first { $0.id == activeID } ?? layouts.first }

    func layout(_ id: UUID) -> Layout? { layouts.first { $0.id == id } }

    func replace(_ layout: Layout) {
        guard let i = layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        let clean = layout.sanitized()
        if layouts[i] != clean { layouts[i] = clean }
    }

    func update(_ id: UUID, _ change: (inout Layout) -> Void) {
        guard var l = layout(id) else { return }
        change(&l)
        replace(l)
    }

    @discardableResult
    func addLayout() -> Layout {
        let l = Layout(name: "Layout \(layouts.count + 1)", rows: [1, 2])
        layouts.append(l)
        return l
    }

    func delete(_ id: UUID) {
        layouts.removeAll { $0.id == id }
        if activeID == id { activeID = layouts.first?.id }
    }

    private func save() {
        guard let url else { return }
        let p = Persisted(layouts: layouts, activeID: activeID, settings: settings)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(p) { try? data.write(to: url, options: .atomic) }
    }
}
