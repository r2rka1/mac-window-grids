import SwiftUI

/// Offscreen rendering with example data, for README screenshots and layout checks.
enum Render {
    static func demoStore() -> Store {
        let s = Store(persist: false)
        func a(_ id: String, _ name: String, _ c: Int, _ r: Int) -> Assignment {
            Assignment(bundleID: id, appName: name, range: CellRange(Cell(col: c, row: r)))
        }
        s.layouts = [
            Layout(
                name: "Coding", columns: [Column(weight: 1.5, rows: 1), Column(weight: 1, rows: 3)],
                assignments: [
                    a("com.apple.dt.Xcode", "Xcode", 0, 0),
                    a("com.apple.Terminal", "Terminal", 1, 0),
                    a("com.apple.Safari", "Safari", 1, 1),
                    a("com.apple.Notes", "Notes", 1, 2),
                ]),
            Layout(
                name: "Writing", rows: [1, 1],
                assignments: [a("com.apple.Notes", "Notes", 0, 0), a("com.apple.Safari", "Safari", 1, 0)]),
            Layout(name: "Comms", rows: [2, 2]),
        ]
        s.activeID = s.layouts[0].id
        return s
    }

    @MainActor static func editor(to path: String, dark: Bool) {
        _ = NSApplication.shared
        let controller = AppController(store: demoStore())
        controller.trusted = true
        let apps = [
            ("com.apple.iCal", "Calendar"), ("com.apple.finder", "Finder"), ("com.apple.mail", "Mail"),
            ("com.apple.Music", "Music"), ("com.apple.Notes", "Notes"), ("com.apple.Safari", "Safari"),
            ("com.apple.Terminal", "Terminal"), ("com.apple.dt.Xcode", "Xcode"),
        ].map { AppRef(bundleID: $0.0, name: $0.1) }
        let view = EditorView(demoApps: apps).environmentObject(controller).environmentObject(controller.store)
            .tint(Mascot.tint)
            .frame(width: 820, height: 640)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: view)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.appearance = appearance
        host.frame = NSRect(x: 0, y: 0, width: 820, height: 640)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        write(host, to: path)
    }

    @MainActor static func overlay(to path: String) {
        _ = NSApplication.shared
        let layout = demoStore().layouts[0]
        let size = CGSize(width: 1280, height: 760)
        let back = NSView(frame: CGRect(origin: .zero, size: size))
        back.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.frame = back.bounds
        gradient.colors = [NSColor(white: 0.32, alpha: 1).cgColor, NSColor(white: 0.18, alpha: 1).cgColor]
        back.layer?.addSublayer(gradient)
        let overlay = OverlayView(frame: back.bounds)
        overlay.layout = layout
        overlay.selection = CellRange(Cell(col: 1, row: 1))
        back.addSubview(overlay)
        let window = NSWindow(contentRect: back.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = back
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        write(back, to: path)
    }

    @MainActor private static func write(_ view: NSView, to path: String) {
        let size = view.bounds.size
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return print("render failed") }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return print("render failed") }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
