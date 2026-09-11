import XCTest
@testable import MediaDrop

final class VideoPresetStorageTests: XCTestCase {
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
        XCTAssertEqual(presets.first { $0.preset.outputFormat == .webp }?.preset.options?.quality, 100)
        XCTAssertEqual(presets.first { $0.preset.outputFormat == .webp }?.preset.options?.moreArguments, ["-cr_size", "0"])
    }

    func testVideoPresetCommandsUseExpectedEncoders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let presets = try PresetStorage(rootDirectory: root).loadVideoPresets().map(\.preset)

        XCTAssertTrue(try XCTUnwrap(presets.first { $0.outputFormat == .mp4 }).ffmpegCommand.contains("-c:v libx264"))
        XCTAssertTrue(try XCTUnwrap(presets.first { $0.outputFormat == .mp3 }).ffmpegCommand.contains("-vn -c:a libmp3lame"))
        XCTAssertTrue(try XCTUnwrap(presets.first { $0.outputFormat == .m4a }).ffmpegCommand.contains("-vn -c:a aac"))
        XCTAssertTrue(try XCTUnwrap(presets.first { $0.outputFormat == .webp }).ffmpegCommand.contains("-vf fps=24 -an -c:v libwebp_anim -quality 100 -loop 0 -cr_size 0"))
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
}
