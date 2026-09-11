import XCTest
@testable import MediaDrop

final class ImageConversionTests: XCTestCase {
    func testImageFFmpegArgumentsAppendMoreArgumentsBeforeOutput() {
        let arguments = ImageFFmpegCommandBuilder.arguments(
            outputFormat: .webp,
            resize: nil,
            options: ImageEncodingOptions(
                quality: 80,
                lossless: false,
                pngPrediction: nil,
                tiffCompression: nil,
                rle: nil,
                globalPalette: nil,
                moreArguments: ["-metadata", "comment=still"]
            ),
            inputURL: URL(fileURLWithPath: "/tmp/input.png"),
            outputURL: URL(fileURLWithPath: "/tmp/output.webp")
        )

        XCTAssertTrue(arguments.containsSubsequence(["-c:v", "libwebp"]))
        XCTAssertEqual(Array(arguments.suffix(4)), ["-metadata", "comment=still", "-y", "/tmp/output.webp"])
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
            "ffmpeg -i \"{input}\" -vf \"scale=1920:1080:force_original_aspect_ratio=decrease\" -c:v libaom-av1 -still-picture 1 -crf 0 -frames:v 1 -y \"{output}\""
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

    func testReservedConversionOutputsAvoidDuplicateNamesInParallelBatch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputs = ImagePresetConversionRunner.reservedOutputURLs(
            for: [
                directory.appendingPathComponent("photo.jpg"),
                directory.appendingPathComponent("photo.png"),
            ],
            outputExtension: "webp"
        ).map(\.outputURL.lastPathComponent)

        XCTAssertEqual(outputs, ["photo.webp", "photo-1.webp"])
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
        XCTAssertTrue(arguments.containsSubsequence(["-frames:v", "1"]))
    }

    func testAnimatedImageOutputKeepsAllFrames() {
        let arguments = ImageFFmpegCommandBuilder.arguments(
            outputFormat: .webp,
            resize: nil,
            options: nil,
            inputURL: URL(fileURLWithPath: "/tmp/input.gif"),
            outputURL: URL(fileURLWithPath: "/tmp/output.webp")
        )

        XCTAssertFalse(arguments.containsSubsequence(["-frames:v", "1"]))
    }

    func testCancelingOneConversionDoesNotCancelAnother() {
        let cancellation = ConversionCancellationController()
        let canceledID = UUID()
        let otherID = UUID()

        cancellation.cancel(canceledID)

        XCTAssertTrue(cancellation.isCanceled(canceledID))
        XCTAssertFalse(cancellation.isCanceled(otherID))
    }
}
