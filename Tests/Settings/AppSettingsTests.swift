import XCTest
@testable import MediaDrop

final class AppSettingsTests: XCTestCase {
    func testDefaultsUseSequentialConversion() {
        let settings = AppSettings()

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.maxConcurrentConversions, 2)
        XCTAssertEqual(settings.multipleFileConversionMode, .sequential)
        XCTAssertEqual(settings.shortcuts[.showConversionPresets], .default)
        XCTAssertEqual(settings.shortcuts[.showConversionPresets].label, "⇧")
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
        XCTAssertEqual(settings.maxConcurrentConversions, 2)
        XCTAssertEqual(settings.multipleFileConversionMode, .sequential)
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
            ModifierShortcut(modifiers: [.option])
        )
        let encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(settings)
        ) as? [String: Any]
        XCTAssertNotNil(encoded?["shortcuts"])
        XCTAssertNil(encoded?["dragShortcut"])
    }

    @MainActor
    func testDragShortcutPersists() throws {
        let suiteName = "MediaDropTests.\(UUID().uuidString)"
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

        XCTAssertEqual(
            AppSettingsStore(defaults: defaults, fileURL: configURL)
                .settings.shortcuts[.showConversionPresets],
            ModifierShortcut(modifiers: [.option])
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
        XCTAssertEqual(
            destination.settings.shortcuts[.showConversionPresets],
            ModifierShortcut(modifiers: [.control])
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

    func testShowConversionShortcutAcceptsOneModifier() {
        XCTAssertEqual(
            ModifierShortcut(modifiers: [.command, .shift]).normalized(for: .showConversionPresets),
            ModifierShortcut(modifiers: [.shift])
        )
        XCTAssertEqual(
            ModifierShortcut(modifiers: [.option]).normalized(for: .showConversionPresets),
            ModifierShortcut(modifiers: [.option])
        )
        XCTAssertEqual(
            RecorderButton.singleModifierCapture(previous: [.command], current: [.command, .shift]),
            .command
        )
    }
}
