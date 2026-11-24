import Foundation

/// A rectangle of grid cells. Row 0 is the top row.
struct CellSpan: Codable, Hashable {
    var col: Int
    var row: Int
    var colSpan: Int = 1
    var rowSpan: Int = 1
}

/// One app window placed in a layout.
struct Assignment: Codable, Identifiable, Hashable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var span: CellSpan
    var screen: Int = 0
}

struct Layout: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var cols: Int
    var rows: Int
    var assignments: [Assignment] = []

    /// Drops or clamps assignments that no longer fit after the grid shrank.
    func sanitized() -> Layout {
        var l = self
        l.cols = min(max(cols, 1), 12)
        l.rows = min(max(rows, 1), 12)
        l.assignments = assignments.compactMap { a in
            guard a.span.col < l.cols, a.span.row < l.rows else { return nil }
            var a = a
            a.span.colSpan = min(max(a.span.colSpan, 1), l.cols - a.span.col)
            a.span.rowSpan = min(max(a.span.rowSpan, 1), l.rows - a.span.row)
            return a
        }
        return l
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
            layouts = p.layouts
            activeID = p.activeID
            settings = p.settings
        } else {
            layouts = [
                Layout(name: "Halves", cols: 2, rows: 1),
                Layout(name: "Thirds", cols: 3, rows: 1),
                Layout(name: "Quarters", cols: 2, rows: 2),
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
        let l = Layout(name: "Layout \(layouts.count + 1)", cols: 2, rows: 2)
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
