import XCTest
@testable import HeheConverter

final class AppSettingsTests: XCTestCase {
    func testDefaultsUseParallelConversion() {
        let settings = AppSettings()

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.maxConcurrentConversions, 3)
        XCTAssertEqual(settings.multipleFileConversionMode, .parallel)
        XCTAssertEqual(settings.imageResizeDefaultScope, .all)
        XCTAssertEqual(settings.imageCompressDefaultScope, .all)
        XCTAssertEqual(settings.enabledImageActions, Set(ImageAction.allCases))
        XCTAssertEqual(settings.enabledVideoActions, Set(VideoAction.allCases))
        XCTAssertEqual(settings.shortcuts[.showConversionPresets], .default)
        XCTAssertEqual(settings.shortcuts[.showConversionPresets].label, "⇧")
        XCTAssertEqual(settings.shortcuts[.showImageActions].label, "⌥⇧")
    }

    func testOldSettingsDecodeWithDefaultDragShortcut() throws {
        let data = Data("""
        {
          "isEnabled": true,
          "triggerScope": "specifiedApps",
          "specifiedApps": [{
            "name": "Finder",
            "bundleIdentifier": "com.apple.finder",
            "isEnabled": true
          }]
        }
        """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.shortcuts[.showConversionPresets], .default)
        XCTAssertEqual(settings.maxConcurrentConversions, 3)
        XCTAssertEqual(settings.multipleFileConversionMode, .parallel)
        XCTAssertEqual(settings.imageResizeDefaultScope, .all)
        XCTAssertEqual(settings.imageCompressDefaultScope, .all)
        XCTAssertEqual(settings.enabledImageActions, Set(ImageAction.allCases))
        XCTAssertEqual(settings.enabledVideoActions, Set(VideoAction.allCases))
        let encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(settings)
        ) as? [String: Any]
        XCTAssertNil(encoded?["triggerScope"])
        XCTAssertNil(encoded?["specifiedApps"])
    }

    func testLegacyDragShortcutMigratesIntoShortcutConfiguration() throws {
        let data = Data("""
        {
          "dragShortcut": {"modifiers": ["option", "shift"]}
        }
        """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(
            settings.shortcuts[.showConversionPresets],
            ModifierShortcut(modifiers: [.option, .shift])
        )
        let encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(settings)
        ) as? [String: Any]
        XCTAssertNotNil(encoded?["shortcuts"])
        XCTAssertNil(encoded?["dragShortcut"])
    }

    func testCropOnlyVideoActionConfigEnablesNewActions() throws {
        let data = Data(#"{"enabledVideoActions":["Crop"]}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.enabledVideoActions, Set(VideoAction.allCases))
    }

    @MainActor
    func testDragShortcutsPersist() throws {
        let suiteName = "HeheConverterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("user_config.json")
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        let store = AppSettingsStore(defaults: defaults, fileURL: configURL)

        store.setShortcut(
            ModifierShortcut(modifiers: [.option, .shift]),
            for: .showConversionPresets
        )
        store.setShortcut(
            ModifierShortcut(modifiers: [.command], key: "A"),
            for: .showImageActions
        )

        let persistedShortcuts = AppSettingsStore(defaults: defaults, fileURL: configURL).settings.shortcuts
        XCTAssertEqual(
            persistedShortcuts[.showConversionPresets],
            ModifierShortcut(modifiers: [.option, .shift])
        )
        XCTAssertEqual(
            persistedShortcuts[.showImageActions],
            ModifierShortcut(modifiers: [.command], key: "A")
        )
    }

    @MainActor
    func testUserConfigExportAndImportRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source/user_config.json")
        let exportURL = root.appendingPathComponent("export/user_config.json")
        let destinationURL = root.appendingPathComponent("destination/user_config.json")
        let source = AppSettingsStore(fileURL: sourceURL)
        source.setEnabled(false)
        source.setMaxConcurrentConversions(4)
        source.setMultipleFileConversionMode(.parallel)
        source.setImageResizeDefaultScope(.each)
        source.setImageCompressDefaultScope(.each)
        source.setImageAction(.crop, isEnabled: false)
        source.setVideoAction(.crop, isEnabled: false)
        source.setShortcut(
            ModifierShortcut(modifiers: [.control, .option]),
            for: .showConversionPresets
        )

        source.exportConfig(to: exportURL)
        let destination = AppSettingsStore(fileURL: destinationURL)
        destination.importConfig(from: exportURL)

        XCTAssertEqual(destination.settings, source.settings)
        XCTAssertEqual(destination.settings.maxConcurrentConversions, 4)
        XCTAssertEqual(destination.settings.multipleFileConversionMode, .parallel)
        XCTAssertEqual(destination.settings.imageResizeDefaultScope, .each)
        XCTAssertEqual(destination.settings.imageCompressDefaultScope, .each)
        XCTAssertFalse(destination.settings.enabledImageActions.contains(.crop))
        XCTAssertFalse(destination.settings.enabledVideoActions.contains(.crop))
        XCTAssertEqual(
            destination.settings.shortcuts[.showConversionPresets],
            ModifierShortcut(modifiers: [.control, .option])
        )
    }

    @MainActor
    func testInvalidUserConfigIsNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configURL = root.appendingPathComponent("user_config.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: configURL)

        let store = AppSettingsStore(fileURL: configURL)

        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), "not json")
    }

    func testShortcutsAcceptModifiersAndAlphanumericKeys() {
        XCTAssertEqual(
            ModifierShortcut(modifiers: [.command, .shift], key: "a").normalized(for: .showConversionPresets),
            ModifierShortcut(modifiers: [.command, .shift], key: "A")
        )
        XCTAssertEqual(
            ModifierShortcut(modifiers: [.option]).normalized(for: .showConversionPresets),
            ModifierShortcut(modifiers: [.option])
        )
        XCTAssertTrue(ModifierShortcut(modifiers: [.control], key: "7").matches(
            modifiers: [.control],
            key: "7"
        ))
    }
}
