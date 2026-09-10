import AppKit
import XCTest
@testable import MediaDrop

final class AppSettingsTests: XCTestCase {
    func testPresetBloomSelectionUsesTopAsFirstSlot() {
        let geometry = PresetBloomGeometry(count: 5, innerRadius: 43, outerRadius: 112)

        XCTAssertEqual(geometry.selectedIndex(deltaX: 0, deltaY: 80), 0)
        XCTAssertEqual(geometry.selectedIndex(deltaX: 80, deltaY: 0), 1)
        XCTAssertEqual(geometry.selectedIndex(deltaX: 0, deltaY: -80), 3)
        XCTAssertNil(geometry.selectedIndex(deltaX: 0, deltaY: 20))
        XCTAssertNil(geometry.selectedIndex(deltaX: 0, deltaY: 130))
    }

    func testDefaultsEnableFinderInSpecifiedApps() {
        let settings = AppSettings()

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.triggerScope, .specifiedApps)
        XCTAssertEqual(settings.specifiedApps, [AllowedApps.finder])
        XCTAssertEqual(settings.shortcuts[.showConversionPresets], .default)
        XCTAssertEqual(settings.shortcuts[.showConversionPresets].label, "⇧")
        XCTAssertTrue(settings.specifiedApps[0].isEnabled)
        XCTAssertEqual(settings.specifiedApps[0].bundleIdentifier, "com.apple.finder")
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
        source.setShortcut(
            ModifierShortcut(modifiers: [.control, .option]),
            for: .showConversionPresets
        )

        source.exportConfig(to: exportURL)
        let destination = AppSettingsStore(fileURL: destinationURL)
        destination.importConfig(from: exportURL)

        XCTAssertEqual(destination.settings, source.settings)
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

    func testFFmpegReleaseDecoderUsesLatestCompatibleTyrrrzReleases() throws {
        let assetName = FFmpegDistribution.assetName
        let data = Data("""
        [
          {
            "tag_name": "9.0.1",
            "draft": false,
            "prerelease": false,
            "assets": [{
              "name": "\(assetName)",
              "size": 123,
              "digest": "sha256:abcdef",
              "browser_download_url": "https://example.com/9.0.1.zip"
            }]
          },
          {
            "tag_name": "9.1-beta",
            "draft": false,
            "prerelease": true,
            "assets": [{
              "name": "\(assetName)",
              "size": 456,
              "digest": "sha256:ignored",
              "browser_download_url": "https://example.com/beta.zip"
            }]
          },
          {
            "tag_name": "8.1.2",
            "draft": false,
            "prerelease": false,
            "assets": [{
              "name": "\(assetName)",
              "size": 789,
              "digest": "sha256:123456",
              "browser_download_url": "https://example.com/8.1.2.zip"
            }]
          }
        ]
        """.utf8)

        let releases = try FFmpegDistribution.decodeReleases(from: data)

        XCTAssertEqual(releases.map(\.version), ["9.0.1", "8.1.2"])
        XCTAssertEqual(releases.first?.asset.name, assetName)
        XCTAssertEqual(releases.first?.asset.size, 123)
        XCTAssertEqual(releases.first?.asset.sha256, "abcdef")
        XCTAssertEqual(releases.first?.asset.downloadURL.absoluteString, "https://example.com/9.0.1.zip")
        XCTAssertEqual(FFmpegDistribution.repository, "Tyrrrz/FFmpegBin")
        XCTAssertEqual(FFmpegDistribution.releaseLimit, 6)
        XCTAssertEqual(
            FFmpegDistribution.releasesAPIURL.absoluteString,
            "https://api.github.com/repos/Tyrrrz/FFmpegBin/releases?per_page=10"
        )
        XCTAssertTrue(FFmpegInstall.binDirectory.path.hasSuffix(".local/com.hoanggbao.MediaDrop/bin"))
    }

    func testFFmpegReleaseDecoderRejectsAssetWithoutChecksum() {
        let data = Data("""
        [{
          "tag_name": "9.0.1",
          "draft": false,
          "prerelease": false,
          "assets": [{
            "name": "\(FFmpegDistribution.assetName)",
            "size": 123,
            "digest": null,
            "browser_download_url": "https://example.com/ffmpeg.zip"
          }]
        }]
        """.utf8)

        XCTAssertThrowsError(try FFmpegDistribution.decodeReleases(from: data))
    }

    func testFFmpegOnboardingOnlyShowsOnceWhenFFmpegIsMissing() {
        XCTAssertTrue(FFmpegOnboarding.shouldShow(isInstalled: false, wasPresented: false))
        XCTAssertFalse(FFmpegOnboarding.shouldShow(isInstalled: true, wasPresented: false))
        XCTAssertFalse(FFmpegOnboarding.shouldShow(isInstalled: false, wasPresented: true))
    }

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
                globalPalette: nil
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
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            json["ffmpegCommand"] as? String,
            "ffmpeg -i \"{input}\" -vf \"scale=1920:ih*0.5\" -c:v libwebp -quality 80 -y \"{output}\""
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

    func testVideoPresetStorageSeedsRequestedBuiltIns() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PresetStorage(rootDirectory: root)

        let presets = try storage.loadVideoPresets()

        XCTAssertEqual(Set(presets.map(\.preset.outputFormat)), Set(VideoOutputFormat.allCases))
        XCTAssertEqual(presets.count, 7)
        XCTAssertTrue(presets.allSatisfy(\.preset.isBuiltIn))
        XCTAssertTrue(presets.allSatisfy { $0.fileURL.deletingLastPathComponent().lastPathComponent == "video" })
        XCTAssertEqual(presets.first { $0.preset.outputFormat == .webp }?.preset.options?.fps, 24)
    }

    func testVideoPresetCommandsUseExpectedEncoders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let presets = try PresetStorage(rootDirectory: root).loadVideoPresets().map(\.preset)

        XCTAssertTrue(try XCTUnwrap(presets.first { $0.outputFormat == .mp4 }).ffmpegCommand.contains("-c:v libx264"))
        XCTAssertTrue(try XCTUnwrap(presets.first { $0.outputFormat == .mp3 }).ffmpegCommand.contains("-vn -c:a libmp3lame"))
        XCTAssertTrue(try XCTUnwrap(presets.first { $0.outputFormat == .m4a }).ffmpegCommand.contains("-vn -c:a aac"))
        XCTAssertTrue(try XCTUnwrap(presets.first { $0.outputFormat == .webp }).ffmpegCommand.contains("-vf fps=24 -an -c:v libwebp_anim -loop 0"))
        XCTAssertEqual(try XCTUnwrap(presets.first { $0.outputFormat == .webp }).name, "WebP")
        XCTAssertEqual(VideoOutputFormat.webp.label, "WEBP")
        XCTAssertEqual(VideoOutputFormat.suggestedFormats, [.mp4, .mov, .webp, .gif, .mp3, .m4a])
        XCTAssertEqual(VideoOutputFormat.format(matching: "mkv"), .mkv)
    }

    func testVideoPresetStorageAddAndUpdate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PresetStorage(rootDirectory: root)
        let preset = VideoPreset(name: "Bản xem trước", outputFormat: .mp4)

        try storage.save(preset)
        let stored = try XCTUnwrap(storage.loadVideoPresets().first { $0.id == preset.id })
        try storage.update(
            stored,
            with: VideoPreset(
                id: preset.id,
                name: "Âm thanh",
                outputFormat: .mp3,
                options: VideoEncodingOptions(
                    quality: nil,
                    resolution: nil,
                    fps: nil,
                    removesAudio: nil,
                    loopCount: nil,
                    audioBitrateKbps: 256
                )
            )
        )

        let updated = try XCTUnwrap(storage.loadVideoPresets().first { $0.id == preset.id })
        XCTAssertEqual(updated.preset.name, "Âm thanh")
        XCTAssertEqual(updated.preset.outputFormat, .mp3)
        XCTAssertTrue(updated.preset.ffmpegCommand.contains("-vn -c:a libmp3lame -b:a 256k"))
    }

    func testVideoFFmpegArgumentsUseOutputFormatExtension() {
        let arguments = VideoFFmpegCommandBuilder.arguments(
            outputFormat: .webp,
            options: VideoEncodingOptions(
                quality: 80,
                resolution: .p720,
                fps: 24,
                removesAudio: nil,
                loopCount: 0,
                audioBitrateKbps: nil
            ),
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/input.webp")
        )

        XCTAssertTrue(arguments.containsSubsequence(["-vf", "fps=24,scale=-2:720"]))
        XCTAssertTrue(arguments.containsSubsequence(["-c:v", "libwebp_anim"]))
        XCTAssertTrue(arguments.containsSubsequence(["-quality", "80"]))
        XCTAssertTrue(arguments.containsSubsequence(["-loop", "0"]))
        XCTAssertEqual(arguments.suffix(2), ["-y", "/tmp/input.webp"])
    }

    func testVideoFFmpegOptionsArePerFormat() {
        let mp4 = VideoFFmpegCommandBuilder.command(
            outputFormat: .mp4,
            options: VideoEncodingOptions(
                quality: 70,
                resolution: .p1080,
                fps: nil,
                removesAudio: true,
                loopCount: nil,
                audioBitrateKbps: nil
            )
        )
        XCTAssertTrue(mp4.contains("-vf scale=-2:1080"))
        XCTAssertTrue(mp4.contains("-crf 18"))
        XCTAssertTrue(mp4.contains("-an"))
        XCTAssertFalse(mp4.contains("fps="))

        let gif = VideoFFmpegCommandBuilder.command(
            outputFormat: .gif,
            options: VideoEncodingOptions(
                quality: 1,
                resolution: .original,
                fps: 12,
                removesAudio: false,
                loopCount: 3,
                audioBitrateKbps: nil
            )
        )
        XCTAssertTrue(gif.contains("[0:v]fps=12,split"))
        XCTAssertTrue(gif.contains("-loop 3"))
        XCTAssertFalse(gif.contains("-crf"))
    }

    func testFFmpegProgressParserReadsRenderedTimestamp() {
        XCTAssertEqual(
            FFmpegProgressParser.seconds(from: "out_time_us=2750000"),
            2.75
        )
        XCTAssertNil(FFmpegProgressParser.seconds(from: "out_time_us=N/A"))
        XCTAssertNil(FFmpegProgressParser.seconds(from: "progress=continue"))
    }

    func testManagedFFmpegImageFormatsExcludeUnsupportedHEIC() {
        XCTAssertTrue(ImageOutputFormat.availableFormats.contains(.avif))
        XCTAssertTrue(ImageOutputFormat.availableFormats.contains(.jpegLS))
        XCTAssertFalse(ImageOutputFormat.availableFormats.contains(.heic))
        XCTAssertEqual(ImageOutputFormat.availableFormat(matching: "webp"), .webp)
        XCTAssertEqual(ImageOutputFormat.availableFormat(matching: " JPEG-LS "), .jpegLS)
        XCTAssertNil(ImageOutputFormat.availableFormat(matching: "heic"))
        XCTAssertEqual(ImageOutputFormat.jpegLS.fileExtension, "jls")
        XCTAssertTrue(ImageOutputFormat.jpg.matches(fileExtension: "jpeg"))
        XCTAssertEqual(
            ImageOutputFormat.suggestedFormats,
            [.jpg, .png, .webp, .avif, .gif, .tiff]
        )
        XCTAssertEqual(ImageOutputFormat.availableFormat(matching: "qoi"), .qoi)
    }

    func testRoundedPixelsKeepFriendlyAspectRatioLabel() {
        XCTAssertEqual(AddImagePresetSheet.aspectRatioLabel(width: 1930, height: 1086), "(16:9)")
        XCTAssertEqual(AddImagePresetSheet.aspectRatioLabel(width: 1302, height: 732), "(16:9)")
    }

    func testImageFFmpegCommandUsesFitWithinAndAVIFLossless() {
        let command = ImageFFmpegCommandBuilder.command(
            outputFormat: .avif,
            resize: ImageResize(
                mode: .fitWithin,
                width: ImageDimension(value: 1920, unit: .pixels),
                height: ImageDimension(value: 1080, unit: .pixels),
                percentage: nil,
                keepAspectRatio: true
            ),
            options: ImageEncodingOptions(
                quality: nil,
                lossless: true,
                pngPrediction: nil,
                tiffCompression: nil,
                rle: nil,
                globalPalette: nil
            )
        )

        XCTAssertEqual(
            command,
            "ffmpeg -i \"{input}\" -vf \"scale=1920:1080:force_original_aspect_ratio=decrease\" -c:v libaom-av1 -still-picture 1 -crf 0 -y \"{output}\""
        )
    }

    func testImageConversionOutputAddsFirstAvailableNumericSuffix() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("photo.png")
        for filename in ["photo.webp", "photo-1.webp", "photo-2.webp"] {
            FileManager.default.createFile(
                atPath: directory.appendingPathComponent(filename).path,
                contents: Data()
            )
        }

        XCTAssertEqual(
            ImagePresetConversionRunner.availableOutputURL(
                for: input,
                outputExtension: "webp"
            ),
            directory.appendingPathComponent("photo-3.webp")
        )
    }

    func testSingleImageConversionSubtitleShowsOutputFilename() {
        XCTAssertEqual(
            ImagePresetConversionRunner.progressSubtitle(
                total: 1,
                saved: 0,
                failed: 0,
                outputFilename: "photo.webp"
            ),
            "photo.webp"
        )
        XCTAssertEqual(
            ImagePresetConversionRunner.progressSubtitle(total: 1, saved: 1, failed: 0),
            "Saved"
        )
    }

    func testTIFFConversionForcesMacOSCompatibleRGBPixels() {
        let arguments = ImageFFmpegCommandBuilder.arguments(
            outputFormat: .tiff,
            resize: nil,
            options: nil,
            inputURL: URL(fileURLWithPath: "/tmp/input.jpg"),
            outputURL: URL(fileURLWithPath: "/tmp/output.tiff")
        )

        XCTAssertTrue(arguments.containsSubsequence(["-pix_fmt", "rgb24"]))
    }

    func testSVGViewportUsesDimensionsViewBoxThenDefault() throws {
        XCTAssertEqual(
            try SVGViewport.size(from: Data("<svg width=\"320\" height=\"180\"></svg>".utf8)),
            CGSize(width: 320, height: 180)
        )
        XCTAssertEqual(
            try SVGViewport.size(from: Data("<svg viewBox=\"0 0 640 360\"></svg>".utf8)),
            CGSize(width: 640, height: 360)
        )
        XCTAssertEqual(
            try SVGViewport.size(from: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)),
            CGSize(width: 512, height: 512)
        )
    }

    @MainActor
    func testSVGRasterizerPreservesTransparentBackground() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let inputURL = directory.appendingPathComponent("transparent.svg")
        let outputURL = directory.appendingPathComponent("transparent.png")
        try Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">
          <circle cx="12" cy="12" r="4" fill="red"/>
        </svg>
        """.utf8).write(to: inputURL)

        try await SVGImageRasterizer.rasterize(inputURL: inputURL, outputURL: outputURL)

        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: outputURL)))
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0, accuracy: 0.01)
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

private extension Array where Element: Equatable {
    func containsSubsequence(_ subsequence: [Element]) -> Bool {
        indices.contains { index in
            let end = index + subsequence.count
            return end <= count && Array(self[index..<end]) == subsequence
        }
    }
}
