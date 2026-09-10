import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var store: AppSettingsStore

    @State private var appEnabled = true
    @State private var launchAtLogin = false
    @State private var finderEnabled = true
    @State private var loginItemError: String?

    private let loginItemService = LoginItemService()

    var body: some View {
        Form {
            Section {
                Toggle("Enable", isOn: $appEnabled)
                    .onChange(of: appEnabled) { value in
                        store.setEnabled(value)
                    }

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { value in
                        updateLaunchAtLogin(value)
                    }

                if let loginItemError {
                    Text(loginItemError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Specified Apps") {
                Toggle("Finder", isOn: $finderEnabled)
                    .onChange(of: finderEnabled) { value in
                        store.setAppEnabled(
                            bundleIdentifier: AllowedApps.finder.bundleIdentifier,
                            isEnabled: value
                        )
                }
            }

            Section("Configuration") {
                HStack {
                    Button("Import…", action: importConfig)
                    Button("Export…", action: exportConfig)
                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .background(OverlayScrollerConfigurator())
        .onAppear {
            appEnabled = store.settings.isEnabled
            launchAtLogin = loginItemService.isEnabled
            finderEnabled = store.settings.specifiedApps.first?.isEnabled ?? true
        }
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try loginItemService.setEnabled(isEnabled)
            launchAtLogin = loginItemService.isEnabled
            loginItemError = nil
        } catch {
            launchAtLogin = loginItemService.isEnabled
            loginItemError = error.localizedDescription
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.importConfig(from: url)
        appEnabled = store.settings.isEnabled
        finderEnabled = store.settings.specifiedApps.first?.isEnabled ?? true
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "user_config.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.exportConfig(to: url)
    }
}
