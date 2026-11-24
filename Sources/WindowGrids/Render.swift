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

    @MainActor static func editorView() -> some View {
        let controller = AppController(store: demoStore())
        controller.trusted = true
        let apps = [
            ("com.apple.iCal", "Calendar"), ("com.apple.finder", "Finder"), ("com.apple.mail", "Mail"),
            ("com.apple.Music", "Music"), ("com.apple.Notes", "Notes"), ("com.apple.Safari", "Safari"),
            ("com.apple.Terminal", "Terminal"), ("com.apple.dt.Xcode", "Xcode"),
        ].map { AppRef(bundleID: $0.0, name: $0.1) }
        return EditorView(demoApps: apps).environmentObject(controller).environmentObject(controller.store)
            .tint(Mascot.tint)
            .frame(width: 820, height: 640)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    @MainActor static func editor(to path: String, dark: Bool) {
        png(of: editorView(), size: CGSize(width: 820, height: 640), dark: dark, to: path)
    }

    @MainActor static func png(of view: some View, size: CGSize, dark: Bool, to path: String) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        write(host, to: path)
    }

    /// App Store screenshots (2880×1800), composed from example data.
    @MainActor static func store(into dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let size = CGSize(width: 1440, height: 900)
        let one = StoreShot(
            title: "Build a grid. Drop your apps in.",
            subtitle: "Every column gets its own width and its own number of rows."
        ) {
            editorView().clipShape(RoundedRectangle(cornerRadius: 12))
        }
        png(of: one, size: size, dark: false, to: dir + "/1.png")
        let two = StoreShot(
            title: "Hold Shift and drag any window",
            subtitle: "The grid appears; drop on a cell and the window snaps into place."
        ) {
            OverlayDemo().frame(width: 1060, height: 630).clipShape(RoundedRectangle(cornerRadius: 12))
        }
        png(of: two, size: size, dark: true, to: dir + "/2.png")
        let three = StoreShot(
            title: "Switch whole layouts with ⌃⌥1 … 9",
            subtitle: "Every app moves to its cell. Apps that are not running are launched."
        ) {
            editorView().clipShape(RoundedRectangle(cornerRadius: 12))
        }
        png(of: three, size: size, dark: true, to: dir + "/3.png")
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

/// The drag overlay over a stand-in desktop.
private struct OverlayDemo: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let back = NSView()
        back.wantsLayer = true
        back.layer?.backgroundColor = NSColor(white: 0.26, alpha: 1).cgColor
        let overlay = OverlayView()
        overlay.layout = Render.demoStore().layouts[0]
        overlay.selection = CellRange(Cell(col: 1, row: 1))
        overlay.autoresizingMask = [.width, .height]
        back.addSubview(overlay)
        return back
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct StoreShot<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                Image(nsImage: Mascot.image(size: 64)).interpolation(.none)
                Text(title).font(.system(size: 50, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            }
            Text(subtitle).font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(Color(nsColor: Mascot.rgb(0xDDD6FE)))
            content()
                .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
                .padding(.top, 26)
            Spacer(minLength: 0)
        }
        .padding(.top, 48)
        .frame(width: 1440, height: 900)
        .background(
            LinearGradient(
                colors: [Color(nsColor: Mascot.rgb(0x4C2FB0)), Color(nsColor: Mascot.rgb(0x150F33))],
                startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
