import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settingsStore: AppSettingsStore
    private var windowController: NSWindowController?

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
    }

    func show() {
        if windowController == nil {
            let content = SettingsView(store: settingsStore)
            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = "MediaDrop Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            windowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }
}

