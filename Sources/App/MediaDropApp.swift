import SwiftUI

@main
struct MediaDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.settingsStore)
        }
    }
}

