import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settingsStore: AppSettingsStore
    private var windowController: NSWindowController?

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
        super.init()
    }

    func show() {
        if windowController == nil {
            let content = SettingsView(store: settingsStore)
            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = "Hehe Converter Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 520, height: 380))
            window.contentMinSize = NSSize(width: 520, height: 380)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            windowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}
