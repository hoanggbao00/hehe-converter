import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let settingsStore: AppSettingsStore
    private let settingsWindowController: SettingsWindowController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var cancellable: AnyCancellable?

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
        settingsWindowController = SettingsWindowController(settingsStore: settingsStore)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "Hehe Converter"
        )
        menu.delegate = self
        statusItem.menu = menu

        cancellable = settingsStore.$settings.sink { [weak self] _ in
            self?.rebuildMenu()
        }
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.addItem(item(title: "Open Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())

        let enabledItem = item(title: "Enabled", action: #selector(toggleEnabled))
        enabledItem.state = settingsStore.settings.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(.separator())
        menu.addItem(item(title: "Quit Hehe Converter", action: #selector(quit), key: "q"))
    }

    private func item(title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func toggleEnabled() {
        settingsStore.setEnabled(!settingsStore.settings.isEnabled)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
