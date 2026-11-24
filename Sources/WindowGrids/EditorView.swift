import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var store: Store
    @State private var selected: UUID?
    /// Fixed app list for rendering screenshots; nil means the apps really running.
    var demoApps: [AppRef]? = nil

    private var currentID: UUID? {
        if let selected, store.layout(selected) != nil { return selected }
        return store.active?.id
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 190)
            Divider()
            if let id = currentID, let index = store.layouts.firstIndex(where: { $0.id == id }) {
                LayoutDetail(
                    layout: Binding(
                        get: { store.layout(id) ?? Layout(name: "", rows: [1]) },
                        set: { store.replace($0) }),
                    index: index)
            } else {
                Text("No layouts. Add one with +.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: Mascot.image(size: 32)).interpolation(.none)
                Text("Window Grids").font(.headline)
            }
            .padding(.bottom, 8)
            Text("LAYOUTS").font(.caption.bold()).foregroundStyle(.secondary).padding(.bottom, 4)
            ForEach(Array(store.layouts.enumerated()), id: \.element.id) { i, l in
                HStack(spacing: 6) {
                    Image(systemName: l.id == store.active?.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(l.id == store.active?.id ? Mascot.tint : .secondary)
                    Text(l.name).lineLimit(1)
                    Spacer()
                    if i < 9 { Text("⌃⌥\(i + 1)").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(l.id == currentID ? Mascot.tint.opacity(0.2) : .clear)
                )
                .contentShape(Rectangle())
                .onTapGesture { selected = l.id }
            }
            HStack {
                Button {
                    selected = store.addLayout().id
                } label: { Image(systemName: "plus") }
                Button {
                    if let id = currentID {
                        store.delete(id)
                        selected = nil
                    }
                } label: { Image(systemName: "minus") }
                .disabled(store.layouts.count <= 1)
            }
            .padding(.top, 6)
            Divider().padding(.vertical, 8)
            AppPalette(demoApps: demoApps)
        }
        .padding(10)
    }
}

private struct LayoutDetail: View {
    @Binding var layout: Layout
    let index: Int
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var store: Store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var screenAspect: CGFloat {
        guard let f = NSScreen.main?.visibleFrame, f.height > 0 else { return 1.6 }
        return f.width / f.height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !controller.trusted { permissionBanner }

            HStack(spacing: 14) {
                TextField("Name", text: $layout.name).textFieldStyle(.roundedBorder).frame(width: 180)
                Stepper("Columns: \(layout.columns.count)", value: columnCount, in: 1...Layout.maxColumns)
                Menu("Preset") {
                    ForEach(Self.presets, id: \.name) { p in
                        Button(p.name) { layout.columns = p.columns }
                    }
                }
                .fixedSize()
                Spacer()
                Button(index < 9 ? "Apply  ⌃⌥\(index + 1)" : "Apply") { controller.apply(layout) }
                    .keyboardShortcut(.defaultAction)
            }

            GridPreview(layout: $layout)
                .aspectRatio(screenAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)

            columnControls

            Text(
                "Drag an app from the list on the left into a cell, or drag a tile to another cell. "
                    + "On screen, hold ⇧ Shift while dragging any window to drop it into a cell of the active "
                    + "layout; add ⌃ Control to stretch it over several cells."
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Capture current windows") { controller.capture(into: layout.id) }
                    .help("Snap every visible window to its nearest cells and store them in this layout")
                Button("Clear apps") { layout.assignments = [] }.disabled(layout.assignments.isEmpty)
                Spacer()
                Text("\(layout.assignments.count) app window\(layout.assignments.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 16) {
                Toggle("Hide other apps on switch", isOn: $store.settings.hideOthers)
                Toggle("Launch missing apps", isOn: $store.settings.launchMissing)
                Toggle("⌃⌥1–9 hotkeys", isOn: $store.settings.hotkeys)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            HStack {
                Text("Gap: \(Int(store.settings.gap)) px")
                Slider(value: $store.settings.gap, in: 0...24, step: 2).frame(width: 180)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Adding appends a single-row column; removing drops the last one.
    private var columnCount: Binding<Int> {
        Binding(
            get: { layout.columns.count },
            set: { n in
                var cols = layout.columns
                while cols.count < n { cols.append(Column()) }
                if cols.count > n { cols.removeLast(cols.count - n) }
                layout.columns = cols
            })
    }

    /// One block per column, laid out under the column it controls.
    private var columnControls: some View {
        let total = layout.columns.reduce(0) { $0 + $1.weight }
        return HStack(alignment: .top, spacing: 6) {
            ForEach(layout.columns.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Column \(i + 1)").font(.caption.bold()).foregroundStyle(.secondary)
                    Stepper("Rows: \(layout.columns[i].rows)", value: $layout.columns[i].rows, in: 1...Layout.maxRows)
                    Stepper(
                        "Width: \(Int((layout.columns[i].weight / total * 100).rounded()))%",
                        value: $layout.columns[i].weight, in: 0.25...4, step: 0.25)
                }
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static let presets: [(name: String, columns: [Column])] = [
        ("Halves", [Column(), Column()]),
        ("Half + 2 rows", [Column(), Column(rows: 2)]),
        ("Half + 3 rows", [Column(), Column(rows: 3)]),
        ("Wide main + 3 rows", [Column(weight: 2), Column(rows: 3)]),
        ("Thirds", [Column(), Column(), Column()]),
        ("Narrow · wide · narrow", [Column(), Column(weight: 2), Column()]),
        ("2 × 2", [Column(rows: 2), Column(rows: 2)]),
        ("3 × 2", [Column(rows: 2), Column(rows: 2), Column(rows: 2)]),
    ]

    private var permissionBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("Window Grids needs Accessibility access to move other apps' windows.")
            Spacer()
            Button("Open Settings…") {
                AX.prompt()
                AX.openSettings()
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.15)))
    }
}

/// A scaled picture of the screen: the grid, and each assigned app in its cells.
private struct GridPreview: View {
    @Binding var layout: Layout

    var body: some View {
        GeometryReader { g in
            let bounds = CGRect(origin: .zero, size: g.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
                ForEach(layout.cells, id: \.self) { cell in
                    let r = rect(CellRange(cell), in: bounds)
                    DropCell { items in drop(items, on: CellRange(cell)) }
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                }
                ForEach(Array(grouped.enumerated()), id: \.offset) { _, group in
                    let r = rect(group.range, in: bounds)
                    AppTile(apps: group.items) { id in
                        layout.assignments.removeAll { $0.id == id }
                    }
                    // A drop on a tile goes to the single cell under the cursor, not the
                    // tile's whole range, so a tile spanning several cells can be split.
                    .dropDestination(for: String.self) { items, location in
                        let p = CGPoint(x: r.minX + location.x, y: bounds.height - (r.minY + location.y))
                        return drop(items, on: CellRange(Geometry.cell(at: p, in: layout, frame: bounds)))
                    }
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                }
                // Cell outlines again, above the tiles, so the grid stays visible under a
                // tile that spans several cells.
                ForEach(layout.cells, id: \.self) { cell in
                    let r = rect(CellRange(cell), in: bounds)
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Handles a drop from the app list ("app:<bundle id>|<name>") or of an existing
    /// tile ("move:<assignment id>").
    private func drop(_ items: [String], on range: CellRange) -> Bool {
        guard let item = items.first else { return false }
        var l = layout
        if item.hasPrefix(DragPayload.move), let id = UUID(uuidString: String(item.dropFirst(DragPayload.move.count))),
            let i = l.assignments.firstIndex(where: { $0.id == id })
        {
            l.assignments[i].range = range
        } else if item.hasPrefix(DragPayload.app) {
            let parts = item.dropFirst(DragPayload.app.count).split(separator: "|", maxSplits: 1)
            guard let bundleID = parts.first.map(String.init), !bundleID.isEmpty else { return false }
            let name = parts.count > 1 ? String(parts[1]) : bundleID
            guard !l.assignments.contains(where: { $0.bundleID == bundleID && $0.range == range })
            else { return true }
            l.assignments.append(Assignment(bundleID: bundleID, appName: name, range: range))
        } else {
            return false
        }
        layout = l
        return true
    }

    /// Assignments sharing the same cells are shown stacked in one tile.
    private var grouped: [(range: CellRange, items: [Assignment])] {
        var order: [CellRange] = []
        var map: [CellRange: [Assignment]] = [:]
        for a in layout.assignments {
            if map[a.range] == nil { order.append(a.range) }
            map[a.range, default: []].append(a)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    /// Cell rect in SwiftUI coordinates (origin top-left).
    private func rect(_ range: CellRange, in bounds: CGRect) -> CGRect {
        let r = Geometry.rect(range, in: layout, frame: bounds, gap: 6)
        return CGRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height)
    }
}

private struct AppTile: View {
    let apps: [Assignment]
    let remove: (UUID) -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(color.opacity(0.28))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(0.9), lineWidth: 1.5))
            .overlay(
                VStack(spacing: 4) {
                    ForEach(apps) { a in
                        HStack(spacing: 5) {
                            if let icon = AppRef.icon(a.bundleID) {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            }
                            Text(a.appName + (a.screen > 0 ? "  (display \(a.screen + 1))" : ""))
                                .font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Button {
                                remove(a.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove from this layout")
                        }
                        .draggable(DragPayload.move + a.id.uuidString)
                    }
                }
                .padding(4)
            )
            .clipped()
    }

    private var color: Color {
        let h = apps.first.map { abs($0.bundleID.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) } ?? 200
        return Color(hue: Double(h) / 360, saturation: 0.65, brightness: 0.8)
    }

}

enum DragPayload {
    static let app = "app:"
    static let move = "move:"
}

struct AppRef: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }

    static func icon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            NSWorkspace.shared.icon(forFile: $0.path)
        }
    }

    static func running() -> [AppRef] {
        let me = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppRef? in
                guard let id = app.bundleIdentifier, id != me, seen.insert(id).inserted else { return nil }
                return AppRef(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// An empty grid cell: a dashed outline that lights up while something is dragged over it.
private struct DropCell: View {
    let onDrop: ([String]) -> Bool
    @State private var targeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(targeted ? Mascot.tint.opacity(0.3) : Color.primary.opacity(0.001))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        targeted ? Mascot.tint : Color.primary.opacity(0.25),
                        style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [] : [4, 3]))
            )
            .dropDestination(for: String.self) { items, _ in onDrop(items) } isTargeted: { targeted = $0 }
    }
}

/// Apps that can be dragged into a cell: everything running, plus any picked by hand.
private struct AppPalette: View {
    let demoApps: [AppRef]?
    @State private var running: [AppRef] = []
    @State private var extra: [AppRef] = []

    private var apps: [AppRef] {
        let base = demoApps ?? running
        return base + extra.filter { e in !base.contains { $0.bundleID == e.bundleID } }
    }

    var body: some View {
        let center = NSWorkspace.shared.notificationCenter
        VStack(alignment: .leading, spacing: 2) {
            Text("APPS").font(.caption.bold()).foregroundStyle(.secondary)
            Text("Drag into a cell").font(.caption).foregroundStyle(.secondary).padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(apps) { app in
                        HStack(spacing: 6) {
                            if let icon = AppRef.icon(app.bundleID) {
                                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                            }
                            Text(app.name).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3).padding(.horizontal, 6)
                        .contentShape(Rectangle())
                        .draggable(DragPayload.app + app.bundleID + "|" + app.name)
                    }
                }
            }
            Button("Other app…", action: pick).controlSize(.small).padding(.top, 4)
        }
        .onAppear { running = AppRef.running() }
        .onReceive(center.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            running = AppRef.running()
        }
        .onReceive(center.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            running = AppRef.running()
        }
    }

    /// Adds an app that is not running to the list.
    private func pick() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !extra.contains(where: { $0.bundleID == id })
            else { continue }
            extra.append(AppRef(bundleID: id, name: FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")))
        }
    }
}
