import SwiftUI

/// Offscreen rendering with example data, for README screenshots and layout checks.
enum Render {
    static func demoStore() -> Store {
        let s = Store(persist: false)
        func a(_ id: String, _ name: String, _ c: Int, _ r: Int, _ cs: Int = 1, _ rs: Int = 1) -> Assignment {
            Assignment(bundleID: id, appName: name, span: CellSpan(col: c, row: r, colSpan: cs, rowSpan: rs))
        }
        s.layouts = [
            Layout(
                name: "Coding", cols: 3, rows: 2,
                assignments: [
                    a("com.apple.dt.Xcode", "Xcode", 0, 0, 2, 2),
                    a("com.apple.Terminal", "Terminal", 2, 0),
                    a("com.apple.Safari", "Safari", 2, 1),
                ]),
            Layout(
                name: "Writing", cols: 2, rows: 1,
                assignments: [a("com.apple.Notes", "Notes", 0, 0), a("com.apple.Safari", "Safari", 1, 0)]),
            Layout(name: "Comms", cols: 2, rows: 2),
        ]
        s.activeID = s.layouts[0].id
        return s
    }

    @MainActor static func editor(to path: String, dark: Bool) {
        _ = NSApplication.shared
        let controller = AppController(store: demoStore())
        controller.trusted = true
        let view = EditorView().environmentObject(controller).environmentObject(controller.store)
            .frame(width: 820, height: 600)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: view)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.appearance = appearance
        host.frame = NSRect(x: 0, y: 0, width: 820, height: 600)
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
        gradient.colors = [NSColor.systemIndigo.cgColor, NSColor.systemTeal.cgColor]
        back.layer?.addSublayer(gradient)
        let overlay = OverlayView(frame: back.bounds)
        overlay.layout = layout
        overlay.selection = CellSpan(col: 2, row: 0, colSpan: 1, rowSpan: 2)
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
