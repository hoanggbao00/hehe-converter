import Foundation

struct AppSettings: Codable, Equatable {
    var isEnabled = true
    var maxConcurrentConversions = 3
    var multipleFileConversionMode: MultipleFileConversionMode = .parallel
    var imageResizeDefaultScope: ResizeApplyScope = .all
    var imageCompressDefaultScope: ResizeApplyScope = .all
    var enabledImageActions = Set(ImageAction.allCases)
    var enabledVideoActions = Set(VideoAction.allCases)
    var enabledVideoCompressOptions = Set(VideoCompressOption.allCases)
    var shortcuts = ShortcutConfiguration.defaults

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        maxConcurrentConversions = max(
            1,
            try container.decodeIfPresent(Int.self, forKey: .maxConcurrentConversions) ?? 3
        )
        multipleFileConversionMode = try container.decodeIfPresent(
            MultipleFileConversionMode.self,
            forKey: .multipleFileConversionMode
        ) ?? .parallel
        imageResizeDefaultScope = try container.decodeIfPresent(
            ResizeApplyScope.self,
            forKey: .imageResizeDefaultScope
        ) ?? .all
        imageCompressDefaultScope = try container.decodeIfPresent(
            ResizeApplyScope.self,
            forKey: .imageCompressDefaultScope
        ) ?? .all
        enabledImageActions = Set(try container.decodeIfPresent(
            [ImageAction].self,
            forKey: .enabledImageActions
        ) ?? ImageAction.allCases)
        let decodedVideoActionNames = try container.decodeIfPresent(
            [String].self,
            forKey: .enabledVideoActions
        )
        let decodedVideoActions = Set(
            decodedVideoActionNames?.compactMap(VideoAction.init(rawValue:)) ?? VideoAction.allCases
        )
        // ponytail: One-time migration for crop-only builds; add a settings schema if another migration is needed.
        enabledVideoActions = decodedVideoActions == [.crop]
            ? Set(VideoAction.allCases)
            : decodedVideoActions
        enabledVideoCompressOptions = Set(try container.decodeIfPresent(
            [VideoCompressOption].self,
            forKey: .enabledVideoCompressOptions
        ) ?? VideoCompressOption.allCases)
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
        try container.encode(maxConcurrentConversions, forKey: .maxConcurrentConversions)
        try container.encode(multipleFileConversionMode, forKey: .multipleFileConversionMode)
        try container.encode(imageResizeDefaultScope, forKey: .imageResizeDefaultScope)
        try container.encode(imageCompressDefaultScope, forKey: .imageCompressDefaultScope)
        try container.encode(
            ImageAction.allCases.filter(enabledImageActions.contains),
            forKey: .enabledImageActions
        )
        try container.encode(
            VideoAction.allCases.filter(enabledVideoActions.contains),
            forKey: .enabledVideoActions
        )
        try container.encode(
            VideoCompressOption.allCases.filter(enabledVideoCompressOptions.contains),
            forKey: .enabledVideoCompressOptions
        )
        try container.encode(shortcuts, forKey: .shortcuts)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case maxConcurrentConversions
        case multipleFileConversionMode
        case imageResizeDefaultScope
        case imageCompressDefaultScope
        case enabledImageActions
        case enabledVideoActions
        case enabledVideoCompressOptions
        case shortcuts
        case dragShortcut
    }
}

enum ResizeApplyScope: String, Codable, CaseIterable, Identifiable {
    case all = "All"
    case each = "Each"

    var id: Self { self }
}

enum MultipleFileConversionMode: String, Codable, CaseIterable, Identifiable {
    case sequential
    case parallel

    var id: Self { self }

    var title: String {
        switch self {
        case .sequential: "Sequential"
        case .parallel: "Parallel"
        }
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case showConversionPresets
    case showImageActions

    var id: Self { self }

    var title: String {
        switch self {
        case .showConversionPresets: "Show conversion presets"
        case .showImageActions: "Show media actions"
        }
    }

    var section: String {
        switch self {
        case .showConversionPresets, .showImageActions: "Drag"
        }
    }

    var defaultShortcut: ModifierShortcut {
        switch self {
        case .showConversionPresets: ModifierShortcut(modifiers: [.shift])
        case .showImageActions: ModifierShortcut(modifiers: [.option, .shift])
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
    let key: String?

    init(modifiers: Set<ShortcutModifier>, key: String? = nil) {
        self.modifiers = modifiers
        self.key = key
    }

    var label: String {
        let modifierLabel = ShortcutModifier.displayOrder
            .filter(modifiers.contains)
            .map(\.symbol)
            .joined()
        return modifierLabel + (key ?? "")
    }

    func normalized(for action: ShortcutAction) -> Self {
        let key = key?.uppercased().first.map(String.init)
        return ModifierShortcut(modifiers: modifiers, key: key)
    }

    func matches(modifiers: Set<ShortcutModifier>, key: String?) -> Bool {
        self.modifiers == modifiers && self.key == key?.uppercased()
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
