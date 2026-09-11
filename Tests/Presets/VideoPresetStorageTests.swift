import XCTest
@testable import MediaDrop

final class VideoPresetStorageTests: XCTestCase {
    func testVideoPresetStorageSeedsRequestedBuiltIns() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PresetStorage(rootDirectory: root)

        let presets = try storage.loadVideoPresets()

        XCTAssertEqual(Set(presets.map(\.preset.outputFormat)), Set([.mp4, .mkv, .mov, .gif, .webp]))
        XCTAssertEqual(presets.count, 5)
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

        XCTAssertTrue(try XCTUnwrap(presets.first { $0.outputFormat == .mp4 }).ffmpegCommand.contains("-c:v h264_videotoolbox"))
        XCTAssertTrue(try XCTUnwrap(presets.first { $0.outputFormat == .webp }).ffmpegCommand.contains("-vf fps=24 -an -c:v libwebp_anim -quality 100 -loop 0 -cr_size 0"))
        XCTAssertEqual(try XCTUnwrap(presets.first { $0.outputFormat == .webp }).name, "WebP")
        XCTAssertEqual(VideoOutputFormat.webp.label, "WEBP")
        XCTAssertEqual(VideoOutputFormat.suggestedFormats, [.mp4, .mov, .webp, .gif])
        XCTAssertEqual(VideoOutputFormat.videoPresetFormats, [.mp4, .mkv, .mov, .avi, .webm, .flv, .m4v, .gif, .webp])
        XCTAssertEqual(VideoOutputFormat.format(matching: "mkv"), .mkv)
        XCTAssertEqual(VideoOutputFormat.format(matching: "avi"), .avi)
        XCTAssertEqual(VideoOutputFormat.format(matching: "webm"), .webm)
        XCTAssertEqual(VideoOutputFormat.format(matching: "flv"), .flv)
        XCTAssertEqual(VideoOutputFormat.format(matching: "m4v"), .m4v)
    }

    func testVideoPresetStorageReplacesOldBuiltInsWithHardwareCommands() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PresetStorage(rootDirectory: root)
        let directory = storage.directory(for: .video)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var oldMP4 = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(
                VideoPreset(name: "MP4", outputFormat: .mp4, isBuiltIn: true)
            )) as? [String: Any]
        )
        oldMP4["ffmpegCommand"] = "ffmpeg -i \"{input}\" -c:v libx264 -c:a aac -movflags +faststart -y \"{output}\""
        try JSONSerialization.data(withJSONObject: oldMP4)
            .write(to: directory.appendingPathComponent("mp4.json"))
        let custom = VideoPreset(name: "Custom MP4", outputFormat: .mp4)
        try JSONEncoder().encode(custom)
            .write(to: directory.appendingPathComponent("custom-mp4.json"))
        try Data("4".utf8).write(to: directory.appendingPathComponent(".seeded"))

        let presets = try storage.loadVideoPresets().map(\.preset)

        XCTAssertTrue(try XCTUnwrap(presets.first { $0.name == "MP4" }).ffmpegCommand.contains("-c:v h264_videotoolbox"))
        XCTAssertTrue(presets.contains { $0.id == custom.id })
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
                name: "WebM preview",
                outputFormat: .webm,
                options: VideoEncodingOptions(
                    quality: 80,
                    fps: nil,
                    removesAudio: false,
                    loopCount: nil,
                    videoBitrateKbps: 2_000,
                    audioBitrateKbps: nil
                )
            )
        )

        let updated = try XCTUnwrap(storage.loadVideoPresets().first { $0.id == preset.id })
        XCTAssertEqual(updated.preset.name, "WebM preview")
        XCTAssertEqual(updated.preset.outputFormat, .webm)
        XCTAssertTrue(updated.preset.ffmpegCommand.contains("-c:v libvpx-vp9 -b:v 2000k"))
    }
}
