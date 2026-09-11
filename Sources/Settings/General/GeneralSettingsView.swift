import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var store: AppSettingsStore

    @State private var appEnabled = true
    @State private var launchAtLogin = false
    @State private var maxConcurrentConversionsText = "3"
    @State private var multipleFileConversionMode = MultipleFileConversionMode.parallel
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

            Section("Conversion") {
                LabeledContent("Parallel conversions") {
                    ScrubbableTextField(
                        text: $maxConcurrentConversionsText,
                        step: 1,
                        usesIntegerValues: true,
                        maximumValue: 8,
                        onChange: updateMaxConcurrentConversions
                    )
                        .frame(width: 56)
                }

                Picker("Multiple-file drops", selection: $multipleFileConversionMode) {
                    ForEach(MultipleFileConversionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: multipleFileConversionMode) { value in
                    store.setMultipleFileConversionMode(value)
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
            maxConcurrentConversionsText = String(store.settings.maxConcurrentConversions)
            multipleFileConversionMode = store.settings.multipleFileConversionMode
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
        maxConcurrentConversionsText = String(store.settings.maxConcurrentConversions)
        multipleFileConversionMode = store.settings.multipleFileConversionMode
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "user_config.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.exportConfig(to: url)
    }

    private func updateMaxConcurrentConversions() {
        guard let value = Int(maxConcurrentConversionsText) else { return }
        let clampedValue = min(max(value, 1), 8)
        if value != clampedValue {
            maxConcurrentConversionsText = String(clampedValue)
        }
        store.setMaxConcurrentConversions(clampedValue)
    }
}
