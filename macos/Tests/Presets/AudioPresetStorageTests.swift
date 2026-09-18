import XCTest
@testable import HeheConverter

final class AudioPresetStorageTests: XCTestCase {
    func testAudioPresetStorageSeedsPopularFormats() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let presets = try PresetStorage(rootDirectory: root).loadAudioPresets()

        XCTAssertEqual(Set(presets.map(\.preset.outputFormat)), Set([.mp3, .m4a, .wav, .flac, .ogg, .opus]))
        XCTAssertEqual(presets.count, 6)
        XCTAssertTrue(presets.allSatisfy(\.preset.isBuiltIn))
        XCTAssertTrue(presets.allSatisfy { $0.fileURL.deletingLastPathComponent().lastPathComponent == "audio" })
        XCTAssertEqual(presets.first { $0.preset.outputFormat == .mp3 }?.preset.options?.audioBitrateKbps, 192)
        XCTAssertEqual(presets.first { $0.preset.outputFormat == .opus }?.preset.options?.audioBitrateKbps, 128)
    }

    func testAudioPresetStorageAddAndUpdate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PresetStorage(rootDirectory: root)
        let preset = VideoPreset(name: "Voice", outputFormat: .mp3)

        try storage.saveAudio(preset)
        let stored = try XCTUnwrap(storage.loadAudioPresets().first { $0.id == preset.id })
        try storage.update(
            stored,
            with: VideoPreset(
                id: preset.id,
                name: "Voice Opus",
                outputFormat: .opus,
                options: VideoEncodingOptions(
                    quality: nil,
                    fps: nil,
                    removesAudio: nil,
                    loopCount: nil,
                    audioBitrateKbps: 96,
                    audioSampleRateHz: 48_000,
                    audioChannels: 1
                )
            )
        )

        let updated = try XCTUnwrap(storage.loadAudioPresets().first { $0.id == preset.id })
        XCTAssertEqual(updated.preset.name, "Voice Opus")
        XCTAssertEqual(updated.preset.outputFormat, .opus)
        XCTAssertTrue(updated.preset.ffmpegCommand.contains("-c:a libopus -b:a 96k -ar 48000 -ac 1"))
    }
}
