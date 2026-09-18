import Foundation

enum AppConstants {
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.hoanggbao.HeheConverter"
    }

    static let managedRootRelativePath = ".local/\(bundleIdentifier)"
    static let managedBinRelativePath = "\(managedRootRelativePath)/bin"
    static let managedPresetsRelativePath = "\(managedRootRelativePath)/presets"
    static let managedTempRelativePath = "\(managedRootRelativePath)/temp"

    static var managedTempURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(managedTempRelativePath, isDirectory: true)
    }

    static var userConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(managedRootRelativePath, isDirectory: true)
            .appendingPathComponent("user_config.json")
    }

    enum DefaultsKey {
        static let appSettings = "appSettings"
        static let didPresentFFmpegOnboarding = "didPresentFFmpegOnboarding"
        static let dismissedAppUpdateVersion = "dismissedAppUpdateVersion"
    }
}
