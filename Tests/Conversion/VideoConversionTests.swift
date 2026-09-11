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
            ),
            backend: .software
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

    func testAdditionalVideoFormatsUseCompatibleCodecs() {
        let options = VideoEncodingOptions(
            quality: 70,
            fps: 24,
            removesAudio: false,
            loopCount: nil,
            audioBitrateKbps: nil
        )

        let avi = VideoFFmpegCommandBuilder.command(outputFormat: .avi, options: options)
        XCTAssertTrue(avi.contains("-c:v mpeg4"))
        XCTAssertTrue(avi.contains("-c:a libmp3lame"))

        let webm = VideoFFmpegCommandBuilder.command(outputFormat: .webm, options: options)
        XCTAssertTrue(webm.contains("-c:v libvpx-vp9"))
        XCTAssertTrue(webm.contains("-c:a libopus"))

        let flv = VideoFFmpegCommandBuilder.command(outputFormat: .flv, options: options)
        XCTAssertTrue(flv.contains("-c:v flv1"))
        XCTAssertTrue(flv.contains("-c:a libmp3lame"))

        let m4v = VideoFFmpegCommandBuilder.command(outputFormat: .m4v, options: options, backend: .software)
        XCTAssertTrue(m4v.contains("-c:v libx264"))
        XCTAssertTrue(m4v.contains("-c:a aac"))
    }

    func testVideoHardwareEncodingIsPreferredWhenAvailable() {
        let mp4 = VideoFFmpegCommandBuilder.command(
            outputFormat: .mp4,
            options: VideoEncodingOptions(
                quality: 70,
                fps: nil,
                removesAudio: false,
                loopCount: nil,
                audioBitrateKbps: nil
            )
        )

        XCTAssertTrue(mp4.contains("-c:v h264_videotoolbox"))
        XCTAssertEqual(VideoFFmpegCommandBuilder.backends(for: .mp4), [.hardware, .software])
        XCTAssertEqual(VideoFFmpegCommandBuilder.backends(for: .webp), [.software])
    }

    func testSelectedHEVCUsesVideoToolboxWithCPUFallback() {
        let options = VideoEncodingOptions(
            quality: 70,
            fps: nil,
            removesAudio: false,
            loopCount: nil,
            audioBitrateKbps: nil,
            codec: .hevc
        )

        XCTAssertTrue(VideoFFmpegCommandBuilder.command(outputFormat: .mp4, options: options).contains("-c:v hevc_videotoolbox"))
        XCTAssertTrue(VideoFFmpegCommandBuilder.command(outputFormat: .mp4, options: options, backend: .software).contains("-c:v libx265"))
        XCTAssertEqual(VideoOutputFormat.mp4.supportedCodecs, [.h264, .hevc])
        XCTAssertTrue(VideoOutputFormat.webm.supportedCodecs.isEmpty)
    }
}
