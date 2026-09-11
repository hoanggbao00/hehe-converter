import XCTest
@testable import HeheConverter

final class ImagePresetStorageTests: XCTestCase {
    func testImagePresetStorageRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PresetStorage(rootDirectory: root)
        let preset = ImagePreset(
            name: "Ảnh động đẹp",
            outputFormat: .webp,
            resize: ImageResize(
                mode: .exactSize,
                width: ImageDimension(value: 1920, unit: .pixels),
                height: ImageDimension(value: 50, unit: .percent),
                percentage: nil,
                keepAspectRatio: false
            ),
            options: ImageEncodingOptions(
                quality: 80,
                lossless: false,
                pngPrediction: nil,
                tiffCompression: nil,
                rle: nil,
                globalPalette: nil,
                moreArguments: ["-pix_fmt", "rgba"]
            )
        )

        try storage.save(preset)

        let savedPreset = try XCTUnwrap(
            storage.loadImagePresets().map(\.preset).first { $0.id == preset.id }
        )
        XCTAssertEqual(savedPreset, preset)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: storage.directory(for: .image)
                    .appendingPathComponent("anh-dong-dep.json")
                    .path
            )
        )

        let data = try Data(
            contentsOf: storage.directory(for: .image)
                .appendingPathComponent("anh-dong-dep.json")
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["id"] as? String, preset.id.uuidString)
        XCTAssertEqual(json["name"] as? String, "Ảnh động đẹp")
        XCTAssertEqual(json["outputFormat"] as? String, "webp")
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        XCTAssertEqual(
            json["ffmpegCommand"] as? String,
            "ffmpeg -i \"{input}\" -vf \"scale=1920:ih*0.5\" -c:v libwebp -quality 80 -pix_fmt rgba -y \"{output}\""
        )
        let resize = try XCTUnwrap(json["resize"] as? [String: Any])
        XCTAssertEqual(resize["mode"] as? String, "exactSize")
        XCTAssertEqual(resize["keepAspectRatio"] as? Bool, false)
        XCTAssertEqual((resize["width"] as? [String: Any])?["value"] as? Double, 1920)
        XCTAssertEqual((resize["width"] as? [String: Any])?["unit"] as? String, "px")
        XCTAssertEqual((resize["height"] as? [String: Any])?["value"] as? Double, 50)
        XCTAssertEqual((resize["height"] as? [String: Any])?["unit"] as? String, "%")
        let options = try XCTUnwrap(json["options"] as? [String: Any])
        XCTAssertEqual(options["quality"] as? Int, 80)
        XCTAssertEqual(options["lossless"] as? Bool, false)
        XCTAssertEqual(options["moreArguments"] as? [String], ["-pix_fmt", "rgba"])
    }

    func testImagePresetStorageDoesNotOverwriteDuplicateSlug() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PresetStorage(rootDirectory: root)

        try storage.save(ImagePreset(name: "Ảnh đẹp", outputFormat: .jpg))
        try storage.save(ImagePreset(name: "Anh dep", outputFormat: .png))

        let filenames = try FileManager.default.contentsOfDirectory(
            at: storage.directory(for: .image),
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .filter { $0.hasPrefix("anh-dep") }
        .sorted()
        XCTAssertEqual(filenames, ["anh-dep-2.json", "anh-dep.json"])
    }

    func testImagePresetStorageSeedsBuiltInConversionPresetsOnce() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PresetStorage(rootDirectory: root)

        let presets = try storage.loadImagePresets()

        XCTAssertEqual(
            Set(presets.map(\.preset.outputFormat)),
            Set([.webp, .png, .jpg, .avif, .tiff])
        )
        XCTAssertEqual(presets.count, 5)
        XCTAssertTrue(presets.allSatisfy { $0.preset.schemaVersion == 2 })
        XCTAssertTrue(presets.allSatisfy { $0.preset.resize == nil })
        XCTAssertTrue(presets.allSatisfy { $0.preset.options == nil })
        XCTAssertTrue(presets.allSatisfy { $0.preset.isBuiltIn })

        try storage.delete(try XCTUnwrap(presets.first { $0.preset.outputFormat == .webp }))

        XCTAssertEqual(try storage.loadImagePresets().count, 4)
    }

    func testImagePresetStorageReplacesBuiltInsOnSeedVersionChange() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PresetStorage(rootDirectory: root)
        let directory = storage.directory(for: .image)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(ImagePreset(name: "BMP", outputFormat: .bmp))
            .write(to: directory.appendingPathComponent("bmp.json"))
        try JSONEncoder().encode(ImagePreset(name: "Custom BMP", outputFormat: .bmp))
            .write(to: directory.appendingPathComponent("custom-bmp.json"))
        try Data().write(to: directory.appendingPathComponent(".seeded"))

        let presets = try storage.loadImagePresets()

        XCTAssertFalse(presets.contains { $0.preset.outputFormat == .bmp && $0.preset.name == "BMP" })
        XCTAssertTrue(presets.contains { $0.preset.outputFormat == .bmp && $0.preset.name == "Custom BMP" })
        XCTAssertTrue(presets.contains { $0.preset.outputFormat == .webp && $0.preset.isBuiltIn })
        XCTAssertTrue(presets.contains { $0.preset.outputFormat == .tiff })
    }

    func testImagePresetStorageReplacesBuiltInsWhenMarkerVersionIsNewer() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PresetStorage(rootDirectory: root)
        let directory = storage.directory(for: .image)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(ImagePreset(name: "Old", outputFormat: .bmp, isBuiltIn: true))
            .write(to: directory.appendingPathComponent("old.json"))
        try Data("999".utf8).write(to: directory.appendingPathComponent(".seeded"))

        let presets = try storage.loadImagePresets()

        XCTAssertFalse(presets.contains { $0.preset.name == "Old" })
        XCTAssertEqual(presets.filter(\.preset.isBuiltIn).count, 5)
    }
}
