import Combine
import SwiftUI

final class AppController: ObservableObject {
    static let shared = AppController()

    let store: Store
    let engine: LayoutEngine
    private let drag: DragController
    private let hotkeys = HotKeys()
    private var bag = Set<AnyCancellable>()
    private var trustTimer: Timer?

    @Published var trusted = AX.trusted

    init(store: Store = Store()) {
        self.store = store
        engine = LayoutEngine(store: store)
        drag = DragController(store: store, engine: engine)
    }

    func start() {
        drag.start()
        hotkeys.onKey = { [weak self] n in self?.applyIndex(n - 1) }
        store.$settings.map(\.hotkeys).removeDuplicates()
            .sink { [weak self] on in self?.hotkeys.setEnabled(on) }
            .store(in: &bag)
        if !trusted { AX.prompt() }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            let now = AX.trusted
            if self?.trusted != now { self?.trusted = now }
        }
    }

    func apply(_ layout: Layout) {
        store.activeID = layout.id
        engine.apply(layout)
    }

    func applyIndex(_ i: Int) {
        guard store.layouts.indices.contains(i) else { return }
        apply(store.layouts[i])
    }

    func capture(into id: UUID) {
        store.activeID = id
        engine.capture(into: id)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
    }
}

struct WindowGridsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var controller = AppController.shared
    @ObservedObject private var store = AppController.shared.store

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(controller).environmentObject(store)
        } label: {
            Image(nsImage: Mascot.image(size: 16, template: true))
        }

        Window("Window Grids", id: "editor") {
            EditorView().environmentObject(controller).environmentObject(store)
                .tint(Mascot.tint)
        }
        .defaultSize(width: 820, height: 600)
    }
}

private struct MenuContent: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !controller.trusted {
            Button("⚠ Grant Accessibility access…") {
                AX.prompt()
                AX.openSettings()
            }
            Divider()
        }
        ForEach(Array(store.layouts.enumerated()), id: \.element.id) { i, layout in
            let button = Button {
                controller.apply(layout)
            } label: {
                if layout.id == store.active?.id {
                    Label(layout.name, systemImage: "checkmark")
                } else {
                    Text(layout.name)
                }
            }
            if i < 9 {
                button.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.control, .option])
            } else {
                button
            }
        }
        Divider()
        if let active = store.active {
            Button("Capture current windows into “\(active.name)”") { controller.capture(into: active.id) }
        }
        Button("Edit Layouts…") {
            openWindow(id: "editor")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Window Grids") { NSApp.terminate(nil) }
    }
}

@main
enum Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            let ok = Geometry.selfTest()
            print(ok ? "selftest ok" : "selftest FAILED")
            exit(ok ? 0 : 1)
        } else if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
            Mascot.writeIcon(.grids, to: args[i + 1])
        } else if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            Render.editor(to: args[i + 1], dark: args.contains("--dark"))
        } else if let i = args.firstIndex(of: "--render-overlay"), i + 1 < args.count {
            Render.overlay(to: args[i + 1])
        } else {
            WindowGridsApp.main()
        }
    }
}
