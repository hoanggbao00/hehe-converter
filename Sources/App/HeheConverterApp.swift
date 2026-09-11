import SwiftUI

@main
struct HeheConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.settingsStore)
        }
    }
}

