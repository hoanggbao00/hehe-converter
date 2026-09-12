import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let storageKey = AppConstants.DefaultsKey.appSettings
    private let fileURL: URL

    init(
        defaults: UserDefaults = .standard,
        fileURL: URL = AppConstants.userConfigURL
    ) {
        self.defaults = defaults
        self.fileURL = fileURL

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                settings = try JSONDecoder().decode(
                    AppSettings.self,
                    from: Data(contentsOf: fileURL)
                )
            } catch {
                settings = AppSettings()
                errorMessage = "Could not load config: \(error.localizedDescription)"
            }
        } else if let data = defaults.data(forKey: storageKey),
                  let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = settings
            save()
        } else {
            settings = AppSettings()
            save()
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        settings.isEnabled = isEnabled
        save()
    }

    func setMaxConcurrentConversions(_ count: Int) {
        settings.maxConcurrentConversions = max(1, count)
        save()
    }

    func setMultipleFileConversionMode(_ mode: MultipleFileConversionMode) {
        settings.multipleFileConversionMode = mode
        save()
    }

    func setImageResizeDefaultScope(_ scope: ResizeApplyScope) {
        settings.imageResizeDefaultScope = scope
        save()
    }

    func setShortcut(_ shortcut: ModifierShortcut, for action: ShortcutAction) {
        guard !shortcut.modifiers.isEmpty else { return }
        settings.shortcuts[action] = shortcut.normalized(for: action)
        save()
    }

    func importConfig(from sourceURL: URL) {
        do {
            let imported = try JSONDecoder().decode(
                AppSettings.self,
                from: Data(contentsOf: sourceURL)
            )
            settings = imported
            try write(settings, to: fileURL)
            errorMessage = nil
        } catch {
            errorMessage = "Could not import config: \(error.localizedDescription)"
        }
    }

    func exportConfig(to destinationURL: URL) {
        do {
            try write(settings, to: destinationURL)
            errorMessage = nil
        } catch {
            errorMessage = "Could not export config: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try write(settings, to: fileURL)
            defaults.removeObject(forKey: storageKey)
            errorMessage = nil
        } catch {
            errorMessage = "Could not save config: \(error.localizedDescription)"
        }
    }

    private func write(_ settings: AppSettings, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}
