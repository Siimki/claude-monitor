import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @StateObject private var store = UsageStore.shared
    @StateObject private var codexStore = CodexStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store, codexStore: codexStore)
        } label: {
            Text(store.labelText)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Makes the process a menu-bar agent (no Dock icon, no main window) and starts
/// the usage refresh loop at launch so the label populates without a click.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if Snapshot.runIfRequested() { exit(0) }
        #endif
        NSApp.setActivationPolicy(.accessory)
        UsageStore.shared.start()
        CodexStore.shared.start()
    }
}
