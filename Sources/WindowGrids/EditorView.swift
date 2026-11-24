import ServiceManagement
import SwiftUI

struct EditorView: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var store: Store
    @State private var selected: UUID?

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
                        get: { store.layout(id) ?? Layout(name: "", cols: 1, rows: 1) },
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
            Text("LAYOUTS").font(.caption.bold()).foregroundStyle(.secondary).padding(.bottom, 4)
            ForEach(Array(store.layouts.enumerated()), id: \.element.id) { i, l in
                HStack(spacing: 6) {
                    Image(systemName: l.id == store.active?.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(l.id == store.active?.id ? Color.accentColor : .secondary)
                    Text(l.name).lineLimit(1)
                    Spacer()
                    if i < 9 { Text("⌃⌥\(i + 1)").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(l.id == currentID ? Color.accentColor.opacity(0.18) : .clear)
                )
                .contentShape(Rectangle())
                .onTapGesture { selected = l.id }
            }
            Spacer()
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
                Stepper("Columns: \(layout.cols)", value: $layout.cols, in: 1...8)
                Stepper("Rows: \(layout.rows)", value: $layout.rows, in: 1...6)
                Spacer()
                Button(index < 9 ? "Apply  ⌃⌥\(index + 1)" : "Apply") { controller.apply(layout) }
                    .keyboardShortcut(.defaultAction)
            }

            GridPreview(layout: $layout)
                .aspectRatio(screenAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)

            Text(
                "Hold ⇧ Shift while dragging any window to drop it into a cell of the active layout. "
                    + "Add ⌃ Control to stretch it over several cells. The app is remembered in that cell."
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
                ForEach(0..<(layout.cols * layout.rows), id: \.self) { i in
                    let span = CellSpan(col: i % layout.cols, row: i / layout.cols)
                    let r = rect(span, in: bounds)
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                }
                ForEach(Array(grouped.enumerated()), id: \.offset) { _, group in
                    let r = rect(group.span, in: bounds)
                    AppTile(apps: group.items) { id in
                        layout.assignments.removeAll { $0.id == id }
                    }
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                }
            }
        }
    }

    /// Assignments sharing the same cells are shown stacked in one tile.
    private var grouped: [(span: CellSpan, items: [Assignment])] {
        var order: [CellSpan] = []
        var map: [CellSpan: [Assignment]] = [:]
        for a in layout.assignments {
            if map[a.span] == nil { order.append(a.span) }
            map[a.span, default: []].append(a)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    /// Cell rect in SwiftUI coordinates (origin top-left).
    private func rect(_ span: CellSpan, in bounds: CGRect) -> CGRect {
        let r = Geometry.rect(span: span, cols: layout.cols, rows: layout.rows, in: bounds, gap: 6)
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
                            if let icon = Self.icon(a.bundleID) {
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

    private static func icon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            NSWorkspace.shared.icon(forFile: $0.path)
        }
    }
}
