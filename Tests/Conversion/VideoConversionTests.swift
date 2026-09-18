import XCTest
@testable import HeheConverter

final class VideoConversionTests: XCTestCase {
    func testVideoFFmpegArgumentsUseOutputFormatExtension() {
        let arguments = VideoFFmpegCommandBuilder.arguments(
            outputFormat: .webp,
            options: VideoEncodingOptions(
                quality: 80,
                fps: 24,
                removesAudio: nil,
                loopCount: 0,
                videoBitrateKbps: nil,
                audioBitrateKbps: nil,
                compressionLevel: 6,
                lossless: false
            ),
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/input.webp")
        )

        XCTAssertTrue(arguments.containsSubsequence(["-vf", "fps=24"]))
        XCTAssertTrue(arguments.containsSubsequence(["-c:v", "libwebp"]))
        XCTAssertTrue(arguments.containsSubsequence(["-lossless", "0"]))
        XCTAssertTrue(arguments.containsSubsequence(["-q:v", "80"]))
        XCTAssertTrue(arguments.containsSubsequence(["-compression_level", "6"]))
        XCTAssertTrue(arguments.containsSubsequence(["-loop", "0"]))
        XCTAssertEqual(arguments.suffix(2), ["-y", "/tmp/input.webp"])
    }

    func testWebPCodecSelectionUsesLibwebpAnim() {
        let arguments = VideoFFmpegCommandBuilder.arguments(
            outputFormat: .webp,
            options: VideoEncodingOptions(
                quality: 90,
                fps: 12,
                removesAudio: nil,
                loopCount: 0,
                videoBitrateKbps: nil,
                audioBitrateKbps: nil,
                compressionLevel: 4,
                lossless: false,
                codec: .libwebpAnim
            ),
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/input.webp")
        )

        XCTAssertTrue(arguments.containsSubsequence(["-c:v", "libwebp_anim"]))
        XCTAssertTrue(arguments.containsSubsequence(["-compression_level", "4"]))
        XCTAssertEqual(VideoOutputFormat.webp.supportedCodecs, [.libwebp, .libwebpAnim])
    }

    func testWebPOmitsCompressionLevelWhenUnset() {
        let arguments = VideoFFmpegCommandBuilder.arguments(
            outputFormat: .webp,
            options: VideoEncodingOptions(
                quality: 90,
                fps: 24,
                removesAudio: nil,
                loopCount: 0,
                videoBitrateKbps: nil,
                audioBitrateKbps: nil,
                lossless: false
            ),
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/input.webp")
        )

        XCTAssertFalse(arguments.contains("-compression_level"))
    }

    func testWebPLosslessOmitsQuality() {
        let arguments = VideoFFmpegCommandBuilder.arguments(
            outputFormat: .webp,
            options: VideoEncodingOptions(
                quality: 90,
                fps: 24,
                removesAudio: nil,
                loopCount: 0,
                videoBitrateKbps: nil,
                audioBitrateKbps: nil,
                compressionLevel: 6,
                lossless: true
            ),
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/input.webp")
        )

        XCTAssertTrue(arguments.containsSubsequence(["-lossless", "1"]))
        XCTAssertFalse(arguments.contains("-q:v"))
    }

    func testVideoFFmpegOptionsArePerFormat() {
        let mp4 = VideoFFmpegCommandBuilder.command(
            outputFormat: .mp4,
            options: VideoEncodingOptions(
                quality: 70,
                fps: nil,
                removesAudio: true,
                loopCount: nil,
                videoBitrateKbps: nil,
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
                videoBitrateKbps: nil,
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
            videoBitrateKbps: nil,
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
                videoBitrateKbps: nil,
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
            videoBitrateKbps: nil,
            audioBitrateKbps: nil,
            codec: .hevc
        )

        XCTAssertTrue(VideoFFmpegCommandBuilder.command(outputFormat: .mp4, options: options).contains("-c:v hevc_videotoolbox"))
        XCTAssertTrue(VideoFFmpegCommandBuilder.command(outputFormat: .mp4, options: options, backend: .software).contains("-c:v libx265"))
        XCTAssertEqual(VideoOutputFormat.mp4.supportedCodecs, [.h264, .hevc])
        XCTAssertTrue(VideoOutputFormat.webm.supportedCodecs.isEmpty)
    }

    func testVideoBitrateOverridesQualityRateControl() {
        let options = VideoEncodingOptions(
            quality: 70,
            fps: nil,
            removesAudio: false,
            loopCount: nil,
            videoBitrateKbps: 4_000,
            audioBitrateKbps: nil
        )

        let arguments = VideoFFmpegCommandBuilder.arguments(
            outputFormat: .mp4,
            options: options,
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            backend: .software
        )

        XCTAssertTrue(arguments.containsSubsequence(["-b:v", "4000k"]))
        XCTAssertFalse(arguments.contains("-crf"))
    }

    func testCustomCommandPresetNormalizesInputAndOutput() throws {
        let preset = try VideoFFmpegCommandBuilder.commandPreset(
            name: "Custom WebM",
            command: "ffmpeg -i \"/tmp/input file.mp4\" -c:v libvpx-vp9 -b:v 0 \"/tmp/output file.webm\""
        )

        XCTAssertEqual(preset.presetType, .command)
        XCTAssertEqual(preset.outputFormat, .webm)
        XCTAssertEqual(preset.options, nil)
        XCTAssertEqual(preset.ffmpegCommand, "ffmpeg -i {input} -c:v libvpx-vp9 -b:v 0 {output}")

        let arguments = try VideoFFmpegCommandBuilder.customArguments(
            command: preset.ffmpegCommand,
            inputURL: URL(fileURLWithPath: "/Users/me/input file.mp4"),
            outputURL: URL(fileURLWithPath: "/Users/me/output file.webm")
        )
        XCTAssertEqual(arguments, [
            "-i", "/Users/me/input file.mp4", "-c:v", "libvpx-vp9", "-b:v", "0", "/Users/me/output file.webm",
        ])
    }

    func testCustomCommandPresetAcceptsBashLineContinuations() throws {
        let preset = try VideoFFmpegCommandBuilder.commandPreset(
            name: "Animated WebP",
            command: """
            ffmpeg -i redpandacompress_banner_football.mp4 \\
            -vf "fps=12,scale=375:-1:flags=lanczos,eq=gamma=1.05:brightness=0.02:saturation=1.03,format=rgba" \\
            -c:v libwebp -lossless 0 -q:v 90 -compression_level 6 -loop 0 -an \\
            redpandacompress_banner_football2.webp
            """
        )

        XCTAssertEqual(preset.outputFormat, .webp)
        XCTAssertEqual(
            preset.ffmpegCommand,
            "ffmpeg -i {input} -vf fps=12,scale=375:-1:flags=lanczos,eq=gamma=1.05:brightness=0.02:saturation=1.03,format=rgba -c:v libwebp -lossless 0 -q:v 90 -compression_level 6 -loop 0 -an {output}"
        )
    }

    func testAdditionalArgumentsTokenizeQuotedWebPScaleFilter() throws {
        let arguments = try VideoFFmpegCommandBuilder.additionalArguments(
            "-vf \"scale=375:-1:flags=lanczos\""
        )

        XCTAssertEqual(arguments, ["-vf", "scale=375:-1:flags=lanczos"])
    }

    func testAdditionalArgumentsPreserveValuesContainingSpaces() throws {
        let arguments = ["-metadata", "comment=hello world"]
        let text = VideoFFmpegCommandBuilder.additionalArgumentsText(arguments)

        XCTAssertEqual(try VideoFFmpegCommandBuilder.additionalArguments(text), arguments)
    }

    func testCustomCommandPresetAcceptsIndentedLineContinuationsAndRepairsStoredNewlines() throws {
        let preset = try VideoFFmpegCommandBuilder.commandPreset(
            name: "Animated WebP",
            command: "ffmpeg -i input.mp4 \\  \n  -vf fps=12 \\ \n  -c:v libwebp output.webp"
        )
        XCTAssertEqual(preset.ffmpegCommand, "ffmpeg -i {input} -vf fps=12 -c:v libwebp {output}")

        let arguments = try VideoFFmpegCommandBuilder.customArguments(
            command: "ffmpeg -i {input} \"\n-vf\" fps=12 \"\n-c:v\" libwebp {output}",
            inputURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.webp")
        )
        XCTAssertEqual(arguments, [
            "-i", "/tmp/input.mp4", "-vf", "fps=12", "-c:v", "libwebp", "/tmp/output.webp",
        ])
    }
}
