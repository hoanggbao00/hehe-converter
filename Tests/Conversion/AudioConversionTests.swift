import XCTest
@testable import HeheConverter

final class AudioConversionTests: XCTestCase {
    func testPopularAudioFormatsUseExpectedCodecsAndOptions() {
        let options = VideoEncodingOptions(
            quality: nil,
            fps: nil,
            removesAudio: nil,
            loopCount: nil,
            audioBitrateKbps: 192,
            audioSampleRateHz: 48_000,
            audioChannels: 2
        )

        let expectedCodecs: [VideoOutputFormat: String] = [
            .mp3: "libmp3lame",
            .m4a: "aac",
            .wav: "pcm_s16le",
            .flac: "flac",
            .ogg: "libvorbis",
            .opus: "libopus",
            .aac: "aac",
        ]

        for (format, codec) in expectedCodecs {
            let arguments = VideoFFmpegCommandBuilder.arguments(
                outputFormat: format,
                options: options,
                inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
                outputURL: URL(fileURLWithPath: "/tmp/output.\(format.fileExtension)")
            )
            XCTAssertTrue(arguments.containsSubsequence(["-vn", "-c:a", codec]), "Missing codec for \(format)")
            XCTAssertTrue(arguments.containsSubsequence(["-ar", "48000"]))
            XCTAssertTrue(arguments.containsSubsequence(["-ac", "2"]))
        }
    }

    func testLosslessFormatsDoNotExposeBitrate() {
        XCTAssertFalse(VideoOutputFormat.wav.supportsAudioBitrate)
        XCTAssertFalse(VideoOutputFormat.flac.supportsAudioBitrate)
        XCTAssertEqual(
            VideoOutputFormat.audioPresetFormats,
            [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aac]
        )
    }
}
