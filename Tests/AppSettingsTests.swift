import XCTest
@testable import MediaDrop

final class AppSettingsTests: XCTestCase {
    func testDefaultsEnableFinderInSpecifiedApps() {
        let settings = AppSettings()

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.triggerScope, .specifiedApps)
        XCTAssertEqual(settings.specifiedApps, [AllowedApps.finder])
        XCTAssertTrue(settings.specifiedApps[0].isEnabled)
        XCTAssertEqual(settings.specifiedApps[0].bundleIdentifier, "com.apple.finder")
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
        XCTAssertEqual(json["schemaVersion"] as? Int, 5)
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
            Set([.webp, .png, .jpg, .bmp, .avif])
        )
        XCTAssertEqual(presets.count, 5)
        XCTAssertTrue(presets.allSatisfy { $0.preset.resize == nil })
        XCTAssertTrue(presets.allSatisfy { $0.preset.options == nil })

        try storage.delete(try XCTUnwrap(presets.first { $0.preset.outputFormat == .webp }))

        XCTAssertEqual(try storage.loadImagePresets().count, 4)
    }

    func testManagedFFmpegImageFormatsExcludeUnsupportedHEIC() {
        XCTAssertTrue(ImageOutputFormat.availableFormats.contains(.avif))
        XCTAssertTrue(ImageOutputFormat.availableFormats.contains(.jpeg2000))
        XCTAssertFalse(ImageOutputFormat.availableFormats.contains(.heic))
        XCTAssertEqual(ImageOutputFormat.availableFormat(matching: "webp"), .webp)
        XCTAssertEqual(ImageOutputFormat.availableFormat(matching: " JPEG 2000 "), .jpeg2000)
        XCTAssertNil(ImageOutputFormat.availableFormat(matching: "heic"))
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
}
