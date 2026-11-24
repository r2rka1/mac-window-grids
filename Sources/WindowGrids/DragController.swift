import AppKit

/// Watches for a window being dragged with Shift held, shows the grid, and snaps the
/// window into the chosen cells on drop.
///
/// Shift alone picks the cell under the cursor. Adding Control anchors the current
/// cell and extends the selection to wherever the cursor goes.
final class DragController {
    private let store: Store
    private let engine: LayoutEngine
    private var monitors: [Any] = []

    private var candidate: (window: AXUIElement, app: NSRunningApplication, first: CGRect)?
    private var confirmed = false
    private var lastCheck = Date.distantPast
    private var anchor: (screen: Int, cell: Cell)?
    private var selection: (screen: Int, range: CellRange)?
    private var overlays: [OverlayWindow] = []

    init(store: Store, engine: LayoutEngine) {
        self.store = store
        self.engine = engine
    }

    func start() {
        guard monitors.isEmpty else { return }
        let add = { (mask: NSEvent.EventTypeMask, handler: @escaping () -> Void) in
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in handler() }) {
                self.monitors.append(m)
            }
        }
        add(.leftMouseDown) { [weak self] in self?.reset() }
        add(.leftMouseDragged) { [weak self] in self?.dragged() }
        add(.leftMouseUp) { [weak self] in self?.dropped() }
    }

    private func reset() {
        candidate = nil
        confirmed = false
        anchor = nil
        selection = nil
        hideOverlay()
    }

    private func dragged() {
        let flags = NSEvent.modifierFlags
        guard flags.contains(.shift), AX.trusted, let layout = store.active else {
            if !overlays.isEmpty {
                hideOverlay()
                anchor = nil
                selection = nil
            }
            return
        }
        if !confirmed {
            guard Date().timeIntervalSince(lastCheck) > 0.06 else { return }
            lastCheck = Date()
            confirmWindowDrag()
            guard confirmed else { return }
        }
        updateSelection(layout: layout, extend: flags.contains(.control))
    }

    /// A drag only counts once the frontmost window is seen moving without changing
    /// size, so Shift-dragging to select text or resize a window does nothing.
    private func confirmWindowDrag() {
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            let window = AX.focusedWindow(pid: app.processIdentifier),
            let frame = AX.frame(of: window)
        else { return }
        if let c = candidate, CFEqual(c.window, window) {
            let moved = hypot(frame.minX - c.first.minX, frame.minY - c.first.minY) > 3
            let sameSize = abs(frame.width - c.first.width) < 2 && abs(frame.height - c.first.height) < 2
            if moved && sameSize { confirmed = true }
        } else {
            candidate = (window, app, frame)
        }
    }

    private func updateSelection(layout: Layout, extend: Bool) {
        let p = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let si = screens.firstIndex(where: { NSMouseInRect(p, $0.frame, false) }) else { return }
        let cell = Geometry.cell(at: p, in: layout, frame: screens[si].visibleFrame)
        if !extend || anchor == nil || anchor?.screen != si { anchor = (si, cell) }
        selection = (si, CellRange(anchor!.cell, cell))
        showOverlay(layout: layout)
        for (i, o) in overlays.enumerated() {
            o.overlay.selection = i == si ? selection?.range : nil
        }
    }

    private func dropped() {
        defer { reset() }
        guard confirmed, !overlays.isEmpty, NSEvent.modifierFlags.contains(.shift),
            let sel = selection, let c = candidate, let layout = store.active,
            let target = engine.targetRect(range: sel.range, screen: sel.screen, in: layout)
        else { return }
        let window = c.window
        let pid = c.app.processIdentifier
        // Let the system finish its own drag first, then place; repeat once because
        // some apps apply their final drag position late.
        for delay in [0.05, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                AX.withoutEnhancedUI(pid: pid) { AX.setFrame(window, target) }
            }
        }
        remember(app: c.app, window: window, range: sel.range, screen: sel.screen, in: layout)
    }

    /// Records the drop in the active layout. If the app already has as many cells as
    /// it has windows, this is a move: drop the cell none of its other windows occupy.
    private func remember(
        app: NSRunningApplication, window: AXUIElement, range: CellRange, screen: Int, in layout: Layout
    ) {
        guard let bundleID = app.bundleIdentifier else { return }
        let all = AX.windows(pid: app.processIdentifier)
        let others = all.filter { !CFEqual($0, window) }.compactMap { AX.frame(of: $0) }
        store.update(layout.id) { l in
            let mine = l.assignments.filter { $0.bundleID == bundleID }
            if mine.count >= max(all.count, 1) {
                let free = mine.first { a in
                    guard let r = engine.targetRect(range: a.range, screen: a.screen, in: l) else { return true }
                    return !others.contains { Geometry.distance($0, r) < 40 }
                }
                if let drop = free ?? mine.first { l.assignments.removeAll { $0.id == drop.id } }
            }
            l.assignments.removeAll { $0.bundleID == bundleID && $0.range == range && $0.screen == screen }
            l.assignments.append(
                Assignment(
                    bundleID: bundleID, appName: app.localizedName ?? bundleID, range: range, screen: screen))
        }
    }

    private func showOverlay(layout: Layout) {
        guard overlays.isEmpty else { return }
        for (i, screen) in NSScreen.screens.enumerated() {
            let w = OverlayWindow(screen: screen, index: i, layout: layout, gap: store.settings.gap)
            w.orderFrontRegardless()
            overlays.append(w)
        }
    }

    private func hideOverlay() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
    }
}
