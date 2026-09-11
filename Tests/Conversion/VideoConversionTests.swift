import XCTest
@testable import MediaDrop

final class VideoConversionTests: XCTestCase {
    func testVideoFFmpegArgumentsUseOutputFormatExtension() {
        let arguments = VideoFFmpegCommandBuilder.arguments(
            outputFormat: .webp,
            options: VideoEncodingOptions(
                quality: 80,
                fps: 24,
                removesAudio: nil,
                loopCount: 0,
                audioBitrateKbps: nil,
                moreArguments: ["-cr_size", "0"]
            ),
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/input.webp")
        )

        XCTAssertTrue(arguments.containsSubsequence(["-vf", "fps=24"]))
        XCTAssertTrue(arguments.containsSubsequence(["-c:v", "libwebp_anim"]))
        XCTAssertTrue(arguments.containsSubsequence(["-quality", "80"]))
        XCTAssertTrue(arguments.containsSubsequence(["-cr_size", "0"]))
        XCTAssertTrue(arguments.containsSubsequence(["-loop", "0"]))
        XCTAssertEqual(Array(arguments.suffix(4)), ["-cr_size", "0", "-y", "/tmp/input.webp"])
        XCTAssertEqual(arguments.suffix(2), ["-y", "/tmp/input.webp"])
    }

    func testVideoFFmpegOptionsArePerFormat() {
        let mp4 = VideoFFmpegCommandBuilder.command(
            outputFormat: .mp4,
            options: VideoEncodingOptions(
                quality: 70,
                fps: nil,
                removesAudio: true,
                loopCount: nil,
                audioBitrateKbps: nil
            )
        )
        XCTAssertFalse(mp4.contains("-vf"))
        XCTAssertFalse(mp4.contains("scale="))
        XCTAssertTrue(mp4.contains("-crf 18"))
        XCTAssertTrue(mp4.contains("-an"))
        XCTAssertFalse(mp4.contains("fps="))

        let gif = VideoFFmpegCommandBuilder.command(
            outputFormat: .gif,
            options: VideoEncodingOptions(
                quality: 1,
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
}
