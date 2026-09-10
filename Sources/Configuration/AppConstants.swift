import Foundation

enum AppConstants {
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.hoanggbao.MediaDrop"
    }

    static let managedRootRelativePath = ".local/\(bundleIdentifier)"
    static let managedBinRelativePath = "\(managedRootRelativePath)/bin"
    static let managedPresetsRelativePath = "\(managedRootRelativePath)/presets"

    enum DefaultsKey {
        static let appSettings = "appSettings"
        static let didPresentFFmpegOnboarding = "didPresentFFmpegOnboarding"
    }
}
