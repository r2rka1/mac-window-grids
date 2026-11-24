import AppKit

/// Moves real windows to match a layout, and reads real windows back into one.
final class LayoutEngine {
    let store: Store
    private var retryToken = 0

    init(store: Store) { self.store = store }

    private var me: pid_t { ProcessInfo.processInfo.processIdentifier }
    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    func screen(_ index: Int) -> NSScreen? {
        let s = NSScreen.screens
        return index < s.count ? s[index] : s.first
    }

    /// Target rect of an assignment in Accessibility coordinates.
    func targetRect(span: CellSpan, screen index: Int, in layout: Layout) -> CGRect? {
        guard let frame = screen(index)?.visibleFrame else { return nil }
        let r = Geometry.rect(
            span: span, cols: layout.cols, rows: layout.rows, in: frame, gap: store.settings.gap)
        return Geometry.flip(r, primaryHeight: primaryHeight)
    }

    private func running(_ bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleID && !$0.isTerminated
        }
    }

    // MARK: apply

    func apply(_ layout: Layout) {
        guard AX.trusted else { return AX.prompt() }
        retryToken += 1
        var order: [String] = []
        var groups: [String: [Assignment]] = [:]
        for a in layout.assignments {
            if groups[a.bundleID] == nil { order.append(a.bundleID) }
            groups[a.bundleID, default: []].append(a)
        }

        if store.settings.hideOthers {
            for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && app.processIdentifier != me
                && !(app.bundleIdentifier.map { groups[$0] != nil } ?? false)
            {
                app.hide()
            }
        }

        var pending: [String] = []
        // Reverse order so the first app in the layout ends up frontmost.
        for bundleID in order.reversed() {
            if let app = running(bundleID) {
                if !place(app, groups[bundleID] ?? [], in: layout) { pending.append(bundleID) }
            } else if store.settings.launchMissing,
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
                pending.append(bundleID)
            }
        }
        if !pending.isEmpty { retry(pending, groups, layout, attempt: 1, token: retryToken) }
    }

    /// Apps that were just launched or unhidden need a moment before they have windows.
    private func retry(
        _ bundleIDs: [String], _ groups: [String: [Assignment]], _ layout: Layout, attempt: Int,
        token: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, token == self.retryToken else { return }
            let left = bundleIDs.filter { id in
                guard let app = self.running(id) else { return true }
                return !self.place(app, groups[id] ?? [], in: layout)
            }
            if !left.isEmpty, attempt < 12 {
                self.retry(left, groups, layout, attempt: attempt + 1, token: token)
            }
        }
    }

    /// Moves the app's windows into its assigned cells. Each assignment takes the window
    /// that is already closest to it, so re-applying does not shuffle windows around.
    @discardableResult
    private func place(_ app: NSRunningApplication, _ list: [Assignment], in layout: Layout) -> Bool {
        if app.isHidden { app.unhide() }
        let pid = app.processIdentifier
        var windows = AX.windows(pid: pid).compactMap { w in AX.frame(of: w).map { (w, $0) } }
        guard !windows.isEmpty else { return false }
        AX.withoutEnhancedUI(pid: pid) {
            for a in list {
                guard !windows.isEmpty,
                    let target = targetRect(span: a.span, screen: a.screen, in: layout)
                else { break }
                let i = windows.indices.min {
                    Geometry.distance(windows[$0].1, target) < Geometry.distance(windows[$1].1, target)
                }!
                let (w, _) = windows.remove(at: i)
                AX.setFrame(w, target)
                AX.raise(w)
            }
        }
        AX.setFrontmost(pid: pid)
        return true
    }

    // MARK: capture

    /// Bounds of normal on-screen windows per process, in Accessibility coordinates.
    private func onScreenBounds() -> [pid_t: [CGRect]] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var result: [pid_t: [CGRect]] = [:]
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                let pid = w[kCGWindowOwnerPID as String] as? Int,
                let b = w[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: b as CFDictionary)
            else { continue }
            result[pid_t(pid), default: []].append(rect)
        }
        return result
    }

    /// Replaces the layout's apps with the windows currently visible, each snapped to
    /// the nearest cells, then applies the layout so the windows line up.
    func capture(into id: UUID) {
        guard AX.trusted else { return AX.prompt() }
        guard let layout = store.layout(id) else { return }
        let visible = onScreenBounds()
        let screens = NSScreen.screens
        var list: [Assignment] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != me {
            guard let bundleID = app.bundleIdentifier, let shown = visible[app.processIdentifier]
            else { continue }
            for w in AX.windows(pid: app.processIdentifier) {
                guard let f = AX.frame(of: w),
                    shown.contains(where: { abs($0.minX - f.minX) < 3 && abs($0.minY - f.minY) < 3 })
                else { continue }
                let r = Geometry.flip(f, primaryHeight: primaryHeight)
                let centre = CGPoint(x: r.midX, y: r.midY)
                let si = screens.firstIndex { $0.frame.contains(centre) } ?? 0
                let span = Geometry.nearestSpan(
                    for: r, cols: layout.cols, rows: layout.rows, in: screens[si].visibleFrame)
                list.append(
                    Assignment(
                        bundleID: bundleID, appName: app.localizedName ?? bundleID, span: span,
                        screen: si))
            }
        }
        store.update(id) { $0.assignments = list }
        if let updated = store.layout(id) { apply(updated) }
    }
}
