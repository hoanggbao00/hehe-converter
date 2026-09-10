import Foundation

enum AppConstants {
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.hoanggbao.MediaDrop"
    }

    static let managedBinRelativePath = ".local/\(bundleIdentifier)/bin"

    enum DefaultsKey {
        static let appSettings = "appSettings"
        static let didPresentFFmpegOnboarding = "didPresentFFmpegOnboarding"
    }
}
