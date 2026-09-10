import Foundation

struct AppSettings: Codable, Equatable {
    var isEnabled = true
    var triggerScope: TriggerScope = .specifiedApps
    var specifiedApps: [AllowedApp] = [AllowedApps.finder]
    var shortcuts = ShortcutConfiguration.defaults

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        triggerScope = try container.decodeIfPresent(TriggerScope.self, forKey: .triggerScope)
            ?? .specifiedApps
        specifiedApps = try container.decodeIfPresent([AllowedApp].self, forKey: .specifiedApps)
            ?? [AllowedApps.finder]
        if let shortcuts = try container.decodeIfPresent(
            ShortcutConfiguration.self,
            forKey: .shortcuts
        ) {
            self.shortcuts = shortcuts
        } else if let legacy = try container.decodeIfPresent(
            ModifierShortcut.self,
            forKey: .dragShortcut
        ) {
            shortcuts[.showConversionPresets] = legacy
        }
        shortcuts.normalize()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(triggerScope, forKey: .triggerScope)
        try container.encode(specifiedApps, forKey: .specifiedApps)
        try container.encode(shortcuts, forKey: .shortcuts)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case triggerScope
        case specifiedApps
        case shortcuts
        case dragShortcut
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case showConversionPresets

    var id: Self { self }

    var title: String {
        switch self {
        case .showConversionPresets: "Show conversion presets"
        }
    }

    var section: String {
        switch self {
        case .showConversionPresets: "Drag"
        }
    }

    var defaultShortcut: ModifierShortcut {
        switch self {
        case .showConversionPresets: ModifierShortcut(modifiers: [.shift])
        }
    }

    var maxModifierCount: Int {
        switch self {
        case .showConversionPresets: 1
        }
    }
}

struct ShortcutConfiguration: Codable, Equatable {
    static let defaults = ShortcutConfiguration(
        bindings: Dictionary(
            uniqueKeysWithValues: ShortcutAction.allCases.map {
                ($0.rawValue, $0.defaultShortcut)
            }
        )
    )

    private var bindings: [String: ModifierShortcut]

    subscript(action: ShortcutAction) -> ModifierShortcut {
        get { (bindings[action.rawValue] ?? action.defaultShortcut).normalized(for: action) }
        set { bindings[action.rawValue] = newValue.normalized(for: action) }
    }

    mutating func normalize() {
        for action in ShortcutAction.allCases {
            self[action] = self[action]
        }
    }
}

struct ModifierShortcut: Codable, Equatable {
    static let `default` = ShortcutAction.showConversionPresets.defaultShortcut

    let modifiers: Set<ShortcutModifier>

    var label: String {
        ShortcutModifier.displayOrder
            .filter(modifiers.contains)
            .map(\.symbol)
            .joined()
    }

    func normalized(for action: ShortcutAction) -> Self {
        let modifiers = ShortcutModifier.displayOrder
            .filter(self.modifiers.contains)
            .prefix(action.maxModifierCount)
        return ModifierShortcut(modifiers: Set(modifiers))
    }
}

enum ShortcutModifier: String, Codable, CaseIterable {
    case control
    case option
    case shift
    case command

    static let displayOrder: [Self] = [.control, .option, .shift, .command]

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }
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
