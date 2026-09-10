import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings

    private let defaults: UserDefaults
    private let storageKey = AppConstants.DefaultsKey.appSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
            ?? AppSettings()
    }

    func setEnabled(_ isEnabled: Bool) {
        settings.isEnabled = isEnabled
        save()
    }

    func setAppEnabled(bundleIdentifier: String, isEnabled: Bool) {
        guard let index = settings.specifiedApps.firstIndex(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else { return }

        settings.specifiedApps[index].isEnabled = isEnabled
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
