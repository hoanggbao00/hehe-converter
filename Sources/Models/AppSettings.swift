import Foundation

struct AppSettings: Codable, Equatable {
    var isEnabled = true
    var triggerScope: TriggerScope = .specifiedApps
    var specifiedApps: [AllowedApp] = [AllowedApps.finder]
}

enum TriggerScope: String, Codable, CaseIterable, Identifiable {
    case specifiedApps

    var id: Self { self }
    var title: String { "Specified Apps" }
}

struct AllowedApp: Codable, Equatable, Identifiable {
    let name: String
    let bundleIdentifier: String
    var isEnabled: Bool

    var id: String { bundleIdentifier }
}
