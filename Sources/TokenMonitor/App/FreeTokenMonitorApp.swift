import AppKit
import SwiftUI

@main
struct FreeTokenMonitorApp: App {
    @NSApplicationDelegateAdaptor(MonitorAppDelegate.self) private var delegate
    @State private var store: MonitorStore

    init() {
        let model = MonitorStore(preview: CommandLine.arguments.contains("--preview") || CommandLine.arguments.contains("--render-preview"))
        _store = State(initialValue: model)
        delegate.store = model
    }

    var body: some Scene {
        MenuBarExtra("Free Token Monitor", systemImage: "chart.bar.xaxis") {
            MonitorPanel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MonitorSettings(store: store)
        }
    }
}

@MainActor
final class MonitorAppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?
    var store: MonitorStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Deliberately lives only in the menu bar: no Dock icon or main window.
        NSApp.setActivationPolicy(.accessory)
        let args = CommandLine.arguments
        let live = args.contains("--render-live")
        guard args.contains("--preview") || args.contains("--render-preview") || live else { return }
        let model = store ?? MonitorStore(preview: !live)
        let panel = MonitorPanel(store: model).background(.regularMaterial)
        let view = NSHostingView(rootView: panel)
        let size = view.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = live ? "Free Token Monitor" : "Free Token Monitor — DEMO"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        previewWindow = window
        NSApp.activate(ignoringOtherApps: true)
        if let index = args.firstIndex(of: live ? "--render-live" : "--render-preview"), args.indices.contains(index + 1) {
            let path = args[index + 1]
            Task { @MainActor in
                if live {
                    for _ in 0..<35 {
                        if model.currentSnapshot != nil || model.errorMessage != nil { break }
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
                try? await Task.sleep(for: .seconds(1))
                view.frame.size = view.fittingSize
                window.setContentSize(view.fittingSize)
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    NSApp.terminate(nil)
                    return
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        }
    }
}
