import XCTest
@testable import HeheConverter

final class DropOverlayTests: XCTestCase {
    @MainActor
    func testMKVIsRecognizedAsVideoWithoutSystemMovieUTI() {
        XCTAssertTrue(DragPresetCoordinator.isVideoURL(URL(fileURLWithPath: "/tmp/movie.MKV")))
        XCTAssertFalse(DragPresetCoordinator.isAudioURL(URL(fileURLWithPath: "/tmp/movie.MKV")))
    }

    @MainActor
    func testDropPresetsKeepVideoAndAudioSeparate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PresetStorage(rootDirectory: root)

        let videoPresets = try DragPresetCoordinator.dropPresets(
            for: [URL(fileURLWithPath: "/tmp/movie.mp4")],
            presetStorage: storage
        )
        let audioPresets = try DragPresetCoordinator.dropPresets(
            for: [URL(fileURLWithPath: "/tmp/audio.mp3")],
            presetStorage: storage
        )

        XCTAssertTrue(videoPresets.allSatisfy(isVideoPreset))
        XCTAssertTrue(audioPresets.allSatisfy(isAudioPreset))
    }

    private func isVideoPreset(_ preset: DropPreset) -> Bool {
        if case .video = preset { return true }
        return false
    }

    private func isAudioPreset(_ preset: DropPreset) -> Bool {
        if case .audio = preset { return true }
        return false
    }

    func testImageActionsKeepReferenceOrderAndIcons() {
        XCTAssertEqual(ImageAction.allCases, [.resize, .crop, .compress])
        XCTAssertEqual(ImageAction.resize.systemImage, "aspectratio")
        XCTAssertEqual(ImageAction.crop.systemImage, "crop")
        XCTAssertEqual(ImageAction.compress.systemImage, "arrow.down.right.and.arrow.up.left")
    }

    func testVideoActionsKeepSingleAndMultipleFileScopes() {
        XCTAssertEqual(VideoAction.actions(forFileCount: 1), [
            .crop, .trim, .speed, .snapshot, .compress, .removeMetadata, .mute, .transform
        ])
        XCTAssertEqual(VideoAction.actions(forFileCount: 2), [
            .removeMetadata, .compress, .mute, .transform
        ])
        XCTAssertEqual(VideoAction.crop.systemImage, "crop")
        XCTAssertEqual(VideoAction.trim.systemImage, "scissors")
        XCTAssertEqual(VideoAction.speed.systemImage, "speedometer")
        XCTAssertEqual(VideoAction.snapshot.systemImage, "camera")
        XCTAssertEqual(VideoAction.compress.systemImage, "arrow.down.right.and.arrow.up.left")
        XCTAssertEqual(VideoAction.removeMetadata.systemImage, "tag.slash")
        XCTAssertEqual(VideoAction.mute.systemImage, "speaker.slash")
        XCTAssertEqual(VideoAction.transform.systemImage, "arrow.up.left.and.arrow.down.right")
    }

    func testVideoCropFFmpegArgumentsPreserveAudioAndUsePixelCropRect() {
        let arguments = VideoCropFFmpegCommandBuilder.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/source video.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output video.mp4"),
            cropRect: CGRect(x: 12, y: 34, width: 640, height: 360)
        )

        XCTAssertEqual(arguments, [
            "-i", "/tmp/source video.mp4",
            "-map", "0:v:0",
            "-map", "0:a?",
            "-vf", "crop=640:360:12:34",
            "-c:v", "libx264",
            "-c:a", "copy",
            "-y", "/tmp/output video.mp4"
        ])
    }

    @MainActor
    func testVideoCropProducesEvenPixelDimensions() {
        let model = VideoCropModel(inputURL: URL(fileURLWithPath: "/tmp/missing.mp4"))
        model.setWidth(33)
        model.setHeight(33)

        let cropRect = model.pixelCropRect()

        XCTAssertEqual(Int(cropRect.minX) % 2, 0)
        XCTAssertEqual(Int(cropRect.minY) % 2, 0)
        XCTAssertEqual(Int(cropRect.width) % 2, 0)
        XCTAssertEqual(Int(cropRect.height) % 2, 0)
    }

    func testVideoCropOutputDoesNotOverwriteSourceOrExistingCrop() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("movie.mp4")
        let firstCrop = directory.appendingPathComponent("movie-cropped.mp4")
        try Data().write(to: inputURL)
        try Data().write(to: firstCrop)

        let outputURL = VideoCropFFmpegRunner.availableOutputURL(for: inputURL)

        XCTAssertEqual(outputURL.lastPathComponent, "movie-cropped-1.mp4")
        XCTAssertNotEqual(outputURL, inputURL)
    }

    func testVideoMuteUsesStreamCopyWithoutAudioAndKeepsInputExtension() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let arguments = try VideoFFmpegCommandBuilder.customArguments(
            command: VideoMuteActionRunner.preset.ffmpegCommand,
            inputURL: URL(fileURLWithPath: "/tmp/source video.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/source video-muted.mov")
        )

        XCTAssertEqual(arguments, [
            "-i", "/tmp/source video.mov",
            "-map", "0",
            "-c", "copy",
            "-an",
            "-y", "/tmp/source video-muted.mov",
        ])

        let jobs = ImagePresetConversionRunner.conversionJobs(
            for: [directory.appendingPathComponent("movie.mkv")],
            outputExtension: "mp4",
            preservesInputExtension: true,
            outputNameSuffix: "muted"
        )

        XCTAssertEqual(jobs.first?.outputURL.lastPathComponent, "movie-muted.mkv")
    }

    func testVideoRemoveMetadataUsesStreamCopyAndKeepsInputExtension() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let arguments = try VideoFFmpegCommandBuilder.customArguments(
            command: VideoRemoveMetadataActionRunner.preset.ffmpegCommand,
            inputURL: URL(fileURLWithPath: "/tmp/source video.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/source video-metadata-removed.mov")
        )

        XCTAssertEqual(arguments, [
            "-i", "/tmp/source video.mov",
            "-map", "0",
            "-c", "copy",
            "-map_metadata", "-1",
            "-map_chapters", "-1",
            "-y", "/tmp/source video-metadata-removed.mov",
        ])

        let jobs = ImagePresetConversionRunner.conversionJobs(
            for: [directory.appendingPathComponent("movie.webm")],
            outputExtension: "mp4",
            preservesInputExtension: true,
            outputNameSuffix: "metadata-removed"
        )

        XCTAssertEqual(jobs.first?.outputURL.lastPathComponent, "movie-metadata-removed.webm")
    }

    @MainActor
    func testVideoSnapshotDefaultsToJPGAndNamesOutputByTimestamp() throws {
        let model = VideoSnapshotModel(inputURL: URL(fileURLWithPath: "/tmp/movie.mp4"))
        XCTAssertEqual(model.format, .jpg)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("movie.mp4")
        let firstSnapshot = directory.appendingPathComponent("movie-snapshot-00-01-05.jpg")
        try Data().write(to: inputURL)
        try Data().write(to: firstSnapshot)

        let outputURL = VideoSnapshotRunner.availableOutputURL(for: inputURL, time: 65.2, format: .jpg)

        XCTAssertEqual(outputURL.lastPathComponent, "movie-snapshot-00-01-05-1.jpg")
    }

    @MainActor
    func testVideoSpeedDefaultsToNormalSpeedAndBuildsSyncedFilters() throws {
        let model = VideoSpeedModel(inputURL: URL(fileURLWithPath: "/tmp/movie.mp4"))
        XCTAssertEqual(model.speed, 1)
        XCTAssertEqual(model.draftSpeed, 1)
        XCTAssertFalse(model.muteAudio)
        XCTAssertFalse(model.canApply)
        model.draftSpeed = 2
        XCTAssertEqual(model.speed, 1)
        XCTAssertFalse(model.canApply)
        model.commitSpeed()
        XCTAssertEqual(model.speed, 2)
        XCTAssertTrue(model.canApply)
        model.muteAudio = true
        XCTAssertTrue(model.canApply)
        XCTAssertEqual(VideoSpeedMath.clamp(0.1), 0.25)
        XCTAssertEqual(VideoSpeedMath.clamp(20), 15)
        XCTAssertEqual(VideoSpeedMath.previewTime(60, speed: 2), 30)
        XCTAssertEqual(VideoSpeedMath.previewTime(60, speed: 0.5), 120)
        XCTAssertEqual(VideoSpeedFFmpegCommandBuilder.atempoFilter(for: 4), "atempo=2,atempo=2")
        XCTAssertEqual(VideoSpeedFFmpegCommandBuilder.atempoFilter(for: 8), "atempo=2,atempo=2,atempo=2")
        XCTAssertEqual(VideoSpeedFFmpegCommandBuilder.atempoFilter(for: 15), "atempo=2,atempo=2,atempo=2,atempo=1.875")
        XCTAssertEqual(VideoSpeedFFmpegCommandBuilder.atempoFilter(for: 0.25), "atempo=0.5,atempo=0.5")

        let arguments = try VideoFFmpegCommandBuilder.customArguments(
            command: VideoSpeedFFmpegRunner.command(speed: 2, muteAudio: false),
            inputURL: URL(fileURLWithPath: "/tmp/source video.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/source video-speed-2x.mp4")
        )

        XCTAssertEqual(arguments, [
            "-i", "/tmp/source video.mp4",
            "-map", "0:v:0",
            "-map", "0:a?",
            "-filter:v", "setpts=0.5*PTS",
            "-filter:a", "atempo=2",
            "-c:v", "libx264",
            "-c:a", "aac",
            "-y", "/tmp/source video-speed-2x.mp4",
        ])

        let mutedArguments = try VideoFFmpegCommandBuilder.customArguments(
            command: VideoSpeedFFmpegRunner.command(speed: 1, muteAudio: true),
            inputURL: URL(fileURLWithPath: "/tmp/source video.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/source video-speed-1x-muted.mp4")
        )

        XCTAssertEqual(mutedArguments, [
            "-i", "/tmp/source video.mp4",
            "-map", "0:v:0",
            "-filter:v", "setpts=1*PTS",
            "-an",
            "-c:v", "libx264",
            "-y", "/tmp/source video-speed-1x-muted.mp4",
        ])
    }

    func testVideoTrimClampsRangeAndBuildsStreamCopyCommand() {
        XCTAssertEqual(VideoTrimMath.range(start: -2, end: 12, duration: 10), 0...10)
        XCTAssertEqual(VideoTrimMath.range(start: 9.98, end: 10, duration: 10), 9.9...10)

        XCTAssertEqual(
            VideoTrimFFmpegCommandBuilder.arguments(
                inputURL: URL(fileURLWithPath: "/tmp/source video.mp4"),
                outputURL: URL(fileURLWithPath: "/tmp/source video-trimmed.mp4"),
                startTime: 1.25,
                endTime: 4.75
            ),
            [
                "-ss", "1.25",
                "-i", "/tmp/source video.mp4",
                "-t", "3.5",
                "-map", "0",
                "-c", "copy",
                "-avoid_negative_ts", "make_zero",
                "-y", "/tmp/source video-trimmed.mp4",
            ]
        )
    }

    func testVideoCropPanelWidthFollowsVideoAspectRatio() {
        let square = VideoCropView.panelWidth(for: CGSize(width: 1000, height: 1000))
        let portrait = VideoCropView.panelWidth(for: CGSize(width: 410, height: 454))
        let landscape = VideoCropView.panelWidth(for: CGSize(width: 1920, height: 1080))

        XCTAssertEqual(square, 348)
        XCTAssertEqual(portrait, 348)
        XCTAssertEqual(landscape, 455)
    }

    @MainActor
    func testVideoCropDefaultsAndResetsToOriginalAspectRatio() {
        let model = VideoCropModel(inputURL: URL(fileURLWithPath: "/tmp/missing.mp4"))

        XCTAssertEqual(model.aspectRatio, .original)
        model.applyAspectRatio(.freeform)
        model.reset()

        XCTAssertEqual(model.aspectRatio, .original)
    }

    func testVideoCropPlaybackRestartsOnlyAtEnd() {
        XCTAssertTrue(VideoCropModel.shouldRestartPlayback(currentTime: 3.98, duration: 4))
        XCTAssertFalse(VideoCropModel.shouldRestartPlayback(currentTime: 3.9, duration: 4))
        XCTAssertFalse(VideoCropModel.shouldRestartPlayback(currentTime: 0, duration: 0))
    }

    func testCropDimensionUnitRangesUsePercentAndPixels() {
        let pixelSize = CGSize(width: 960, height: 718)

        XCTAssertEqual(CropDimensionUnit.percent.rawValue, "%")
        XCTAssertEqual(CropDimensionUnit.pixels.rawValue, "px")
        XCTAssertEqual(CropDimensionUnit.percent.range(for: pixelSize, axis: .horizontal), 1...100)
        XCTAssertEqual(CropDimensionUnit.pixels.range(for: pixelSize, axis: .horizontal), 1...960)
        XCTAssertEqual(CropDimensionUnit.pixels.range(for: pixelSize, axis: .vertical), 1...718)
    }

    @MainActor
    func testCropPreviewFitsImageWithoutOuterGutters() {
        let model = ImageCropModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))

        let size = model.previewSize(fitting: CGSize(width: 280, height: 210))

        XCTAssertEqual(size.width, 280, accuracy: 0.001)
        XCTAssertEqual(size.height, 209.416, accuracy: 0.001)
    }

    @MainActor
    func testCropPositionStaysInsideImageBounds() {
        let model = ImageCropModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))
        model.setHeight(62)

        model.moveCrop(from: CGPoint(x: 0.5, y: 0.5), translation: CGSize(width: 2, height: 2))

        XCTAssertEqual(model.cropCenter.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(model.cropCenter.y, 0.69, accuracy: 0.001)
    }

    @MainActor
    func testCropDefaultsAndResetsToFullImage() {
        let model = ImageCropModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))

        XCTAssertEqual(model.normalizedCropRect(), CGRect(x: 0, y: 0, width: 1, height: 1))

        model.setWidth(50)
        model.setHeight(50)
        model.reset()

        XCTAssertEqual(model.normalizedCropRect(), CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @MainActor
    func testCropPositionReclampsWhenSizeGrows() {
        let model = ImageCropModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))
        model.setWidth(50)
        model.moveCrop(from: CGPoint(x: 0.5, y: 0.5), translation: CGSize(width: 2, height: 0))

        model.setWidth(100)

        XCTAssertEqual(model.cropCenter.x, 0.5, accuracy: 0.001)
    }

    @MainActor
    func testCropResizeHandlesUpdateSizeAndCenter() {
        let model = ImageCropModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))
        model.setWidth(50)
        model.setHeight(50)

        model.resizeCrop(
            handle: .right,
            from: model.normalizedCropRect(),
            translation: CGSize(width: 0.25, height: 0)
        )

        XCTAssertEqual(model.width, 75, accuracy: 0.001)
        XCTAssertEqual(model.height, 50, accuracy: 0.001)
        XCTAssertEqual(model.cropCenter.x, 0.625, accuracy: 0.001)

        model.resizeCrop(
            handle: .topLeft,
            from: model.normalizedCropRect(),
            translation: CGSize(width: -2, height: -2)
        )

        XCTAssertEqual(model.width, 100, accuracy: 0.001)
        XCTAssertEqual(model.height, 75, accuracy: 0.001)
        XCTAssertEqual(model.cropCenter.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(model.cropCenter.y, 0.375, accuracy: 0.001)
    }

    func testCropShowsEightResizeHandles() {
        XCTAssertEqual(CropHandlePosition.allCases.count, 8)
    }

    @MainActor
    func testCropRatioKeepsSlidersAndHandlesInSync() {
        let model = ImageCropModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))
        model.applyUnit(.pixels)
        model.applyAspectRatio(.sixteenNine)

        model.setWidth(640)

        XCTAssertEqual(model.width, 640, accuracy: 0.001)
        XCTAssertEqual(model.height, 360, accuracy: 0.001)

        model.resizeCrop(
            handle: .bottom,
            from: model.normalizedCropRect(),
            translation: CGSize(width: 0, height: 0.1)
        )

        XCTAssertEqual(model.width / model.height, 16.0 / 9.0, accuracy: 0.01)
    }

    func testCropOffersPopularAspectRatios() {
        XCTAssertEqual(
            CropAspectRatio.allCases,
            [.original, .freeform, .square, .fourThree, .threeFour, .threeTwo, .twoThree, .sixteenNine, .nineSixteen]
        )
    }

    func testCropFFmpegArgumentsUsePixelCropRect() {
        let arguments = ImageCropFFmpegCommandBuilder.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/source image.png"),
            outputURL: URL(fileURLWithPath: "/tmp/output image.png"),
            cropRect: CGRect(x: 12, y: 34, width: 640, height: 360)
        )

        XCTAssertEqual(arguments, [
            "-i", "/tmp/source image.png",
            "-vf", "crop=640:360:12:34",
            "-frames:v", "1",
            "-y", "/tmp/output image.png"
        ])
    }

    func testCropAnimatedWebPPreservesAnimation() {
        let arguments = ImageCropFFmpegCommandBuilder.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/source image.webp"),
            outputURL: URL(fileURLWithPath: "/tmp/output image.webp"),
            cropRect: CGRect(x: 12, y: 34, width: 640, height: 360),
            isAnimatedWebP: true
        )

        XCTAssertEqual(arguments, [
            "-i", "/tmp/source image.webp",
            "-vf", "crop=640:360:12:34",
            "-an",
            "-c:v", "libwebp_anim",
            "-loop", "0",
            "-y", "/tmp/output image.webp"
        ])
        XCTAssertFalse(arguments.contains("-frames:v"))
    }

    func testCropOutputDoesNotOverwriteSourceOrExistingCrop() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("photo.png")
        let firstCrop = directory.appendingPathComponent("photo-cropped.png")
        try Data().write(to: inputURL)
        try Data().write(to: firstCrop)

        let outputURL = ImageCropFFmpegRunner.availableOutputURL(for: inputURL)

        XCTAssertEqual(outputURL.lastPathComponent, "photo-cropped-1.png")
        XCTAssertNotEqual(outputURL, inputURL)
    }

    @MainActor
    func testResizeDefaultsToOriginalSizeAndConvertsUnits() {
        let model = ImageResizeModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))

        XCTAssertEqual(model.unit, .percent)
        XCTAssertEqual(model.width, 100)
        XCTAssertEqual(model.height, 100)
        XCTAssertTrue(model.keepsAspectRatio)
        XCTAssertEqual(model.outputPixelSize, CGSize(width: 960, height: 718))
        XCTAssertEqual(model.range(for: .horizontal), 1...100)

        model.applyUnit(.pixels)

        XCTAssertEqual(model.width, 960)
        XCTAssertEqual(model.height, 718)
    }

    @MainActor
    func testResizeAspectLockUpdatesOtherDimension() {
        let model = ImageResizeModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))
        model.applyUnit(.pixels)

        model.setWidth(480)

        XCTAssertEqual(model.width, 480)
        XCTAssertEqual(model.height, 359)

        model.setKeepsAspectRatio(false)
        model.setHeight(200)

        XCTAssertEqual(model.width, 480)
        XCTAssertEqual(model.height, 200)
    }

    @MainActor
    func testResizePreviewHandlesUpdateDimensions() {
        let model = ImageResizeModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))
        model.setWidth(50)

        model.resizePreview(
            handle: .topLeft,
            from: model.outputPixelSize,
            translation: CGSize(width: -96, height: -72),
            in: CGSize(width: 960, height: 718)
        )

        XCTAssertEqual(model.width, 60)
        XCTAssertEqual(model.height, 60)

        model.setKeepsAspectRatio(false)
        model.resizePreview(
            handle: .bottomRight,
            from: model.outputPixelSize,
            translation: CGSize(width: 96, height: 0),
            in: CGSize(width: 960, height: 718)
        )

        XCTAssertEqual(model.width, 70)
        XCTAssertEqual(model.height, 60)
    }

    func testResizeShowsFourCornerHandles() {
        XCTAssertEqual(ResizeHandlePosition.allCases.count, 4)
    }

    func testResizeOffersAllAndEachScopes() {
        XCTAssertEqual(ResizeApplyScope.allCases, [.all, .each])
    }

    @MainActor
    func testResizeAllPercentUsesEachImageOriginalSize() {
        let settings = ImageResizeSettings(unit: .percent, width: 50, height: 50)

        XCTAssertEqual(
            ImageResizeModel.outputPixelSize(for: CGSize(width: 1_000, height: 500), settings: settings),
            CGSize(width: 500, height: 250)
        )
        XCTAssertEqual(
            ImageResizeModel.outputPixelSize(for: CGSize(width: 200, height: 100), settings: settings),
            CGSize(width: 100, height: 50)
        )
    }

    @MainActor
    func testResizeAllPixelsUsesSharedBoundingBox() {
        let settings = ImageResizeSettings(unit: .pixels, width: 640, height: 480)

        XCTAssertEqual(
            ImageResizeModel.outputPixelSize(for: CGSize(width: 1_000, height: 500), settings: settings),
            CGSize(width: 640, height: 480)
        )
    }

    func testResizeFFmpegArgumentsUseExactOutputSize() {
        let arguments = ImageResizeFFmpegCommandBuilder.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/source image.png"),
            outputURL: URL(fileURLWithPath: "/tmp/output image.png"),
            outputPixelSize: CGSize(width: 640, height: 360)
        )

        XCTAssertEqual(arguments, [
            "-i", "/tmp/source image.png",
            "-vf", "scale=640:360:force_original_aspect_ratio=decrease:flags=lanczos",
            "-frames:v", "1",
            "-y", "/tmp/output image.png"
        ])
    }

    func testResizeAnimatedWebPPreservesAnimation() {
        let arguments = ImageResizeFFmpegCommandBuilder.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/source image.webp"),
            outputURL: URL(fileURLWithPath: "/tmp/output image.webp"),
            outputPixelSize: CGSize(width: 640, height: 360),
            isAnimatedWebP: true
        )

        XCTAssertEqual(arguments, [
            "-i", "/tmp/source image.webp",
            "-vf", "scale=640:360:force_original_aspect_ratio=decrease:flags=lanczos",
            "-an",
            "-c:v", "libwebp_anim",
            "-loop", "0",
            "-y", "/tmp/output image.webp"
        ])
        XCTAssertFalse(arguments.contains("-frames:v"))
    }

    func testResizeOutputDoesNotOverwriteSourceOrExistingResize() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("photo.png")
        let firstResize = directory.appendingPathComponent("photo-resized.png")
        try Data().write(to: inputURL)
        try Data().write(to: firstResize)

        let outputURL = ImageResizeFFmpegRunner.availableOutputURL(for: inputURL)

        XCTAssertEqual(outputURL.lastPathComponent, "photo-resized-1.png")
        XCTAssertNotEqual(outputURL, inputURL)
    }

    func testCompressFFmpegArgumentsUseJpegQualityAndStripMetadata() throws {
        let arguments = try ImageCompressFFmpegCommandBuilder.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/source image.jpg"),
            outputURL: URL(fileURLWithPath: "/tmp/output image.jpg"),
            quality: 80,
            stripsMetadata: true
        )

        XCTAssertEqual(arguments, [
            "-i", "/tmp/source image.jpg",
            "-map_metadata", "-1",
            "-c:v", "mjpeg",
            "-q:v", "8",
            "-frames:v", "1",
            "-y", "/tmp/output image.jpg"
        ])
    }

    func testCompressFFmpegArgumentsKeepMetadataWhenRequested() throws {
        let arguments = try ImageCompressFFmpegCommandBuilder.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/source image.webp"),
            outputURL: URL(fileURLWithPath: "/tmp/output image.webp"),
            quality: 72,
            stripsMetadata: false
        )

        XCTAssertEqual(arguments, [
            "-i", "/tmp/source image.webp",
            "-c:v", "libwebp",
            "-quality", "72",
            "-frames:v", "1",
            "-y", "/tmp/output image.webp"
        ])
    }

    func testCompressAnimatedWebPPreservesAnimationAndAppliesFPS() throws {
        let arguments = try ImageCompressFFmpegCommandBuilder.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/source image.webp"),
            outputURL: URL(fileURLWithPath: "/tmp/output image.webp"),
            quality: 72,
            stripsMetadata: true,
            isAnimatedWebP: true,
            fps: 12
        )

        XCTAssertEqual(arguments, [
            "-i", "/tmp/source image.webp",
            "-map_metadata", "-1",
            "-vf", "fps=12",
            "-an",
            "-c:v", "libwebp_anim",
            "-quality", "72",
            "-loop", "0",
            "-y", "/tmp/output image.webp"
        ])
        XCTAssertFalse(arguments.contains("-frames:v"))
    }

    func testCompressFFmpegArgumentsUsePngCompressionLevel() throws {
        let arguments = try ImageCompressFFmpegCommandBuilder.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/source image.png"),
            outputURL: URL(fileURLWithPath: "/tmp/output image.png"),
            quality: 80,
            stripsMetadata: true,
            pngCompressionLevel: 4
        )

        XCTAssertEqual(arguments, [
            "-i", "/tmp/source image.png",
            "-map_metadata", "-1",
            "-c:v", "png",
            "-compression_level", "4",
            "-frames:v", "1",
            "-y", "/tmp/output image.png"
        ])
    }

    func testCompressQualityMappingsClampToCodecRanges() {
        XCTAssertEqual(ImageCompressFFmpegCommandBuilder.jpegQScale(for: 100), 2)
        XCTAssertEqual(ImageCompressFFmpegCommandBuilder.jpegQScale(for: 80), 8)
        XCTAssertEqual(ImageCompressFFmpegCommandBuilder.jpegQScale(for: 1), 31)
        XCTAssertEqual(ImageCompressFFmpegCommandBuilder.avifCRF(for: 100), 0)
        XCTAssertEqual(ImageCompressFFmpegCommandBuilder.avifCRF(for: 80), 13)
        XCTAssertEqual(ImageCompressFFmpegCommandBuilder.avifCRF(for: 1), 63)
    }

    func testCompressOutputDoesNotOverwriteSourceOrExistingCompress() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("photo.jpg")
        let firstCompress = directory.appendingPathComponent("photo-compressed.jpg")
        try Data().write(to: inputURL)
        try Data().write(to: firstCompress)

        let outputURL = ImageCompressFFmpegRunner.availableOutputURL(for: inputURL)

        XCTAssertEqual(outputURL.lastPathComponent, "photo-compressed-1.jpg")
        XCTAssertNotEqual(outputURL, inputURL)
    }

    func testCompressSupportsOnlyKnownImageFormats() throws {
        XCTAssertNoThrow(try ImageCompressFFmpegCommandBuilder.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/photo.avif"),
            outputURL: URL(fileURLWithPath: "/tmp/photo-compressed.avif"),
            quality: 80,
            stripsMetadata: true
        ))
        XCTAssertThrowsError(try ImageCompressFFmpegCommandBuilder.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/photo.tiff"),
            outputURL: URL(fileURLWithPath: "/tmp/photo-compressed.tiff"),
            quality: 80,
            stripsMetadata: true
        ))
    }

    func testCompressPreviewTempUsesAppManagedTempDirectory() throws {
        let url = try ImageCompressFFmpegRunner.previewTempURL(
            for: URL(fileURLWithPath: "/tmp/photo.jpg")
        )

        XCTAssertTrue(url.path.hasPrefix(
            AppConstants.managedTempURL.appendingPathComponent("compress-preview").path
        ))
        XCTAssertEqual(url.pathExtension, "jpg")
    }

    func testResizeAndCropPreviewTempsUseAppManagedTempDirectory() throws {
        let inputURL = URL(fileURLWithPath: "/tmp/photo.jpg")
        let resizeURL = try ImageResizeFFmpegRunner.previewTempURL(for: inputURL)
        let cropURL = try ImageCropFFmpegRunner.previewTempURL(for: inputURL)

        XCTAssertTrue(resizeURL.path.hasPrefix(
            AppConstants.managedTempURL.appendingPathComponent("resize-preview").path
        ))
        XCTAssertTrue(cropURL.path.hasPrefix(
            AppConstants.managedTempURL.appendingPathComponent("crop-preview").path
        ))
        XCTAssertEqual(resizeURL.pathExtension, "jpg")
        XCTAssertEqual(cropURL.pathExtension, "jpg")
    }

    func testPresetBloomSelectionUsesTopAsFirstSlot() {
        let geometry = PresetBloomGeometry(count: 5, innerRadius: 43, outerRadius: 112)

        XCTAssertEqual(geometry.selectedIndex(deltaX: 0, deltaY: 80), 0)
        XCTAssertEqual(geometry.selectedIndex(deltaX: 80, deltaY: 0), 1)
        XCTAssertEqual(geometry.selectedIndex(deltaX: 0, deltaY: -80), 3)
        XCTAssertNil(geometry.selectedIndex(deltaX: 0, deltaY: 20))
        XCTAssertNil(geometry.selectedIndex(deltaX: 0, deltaY: 130))
    }

    func testIndeterminateProgressThumbMovesBackAndForth() {
        XCTAssertEqual(AccentProgressBar.indeterminateOffset(at: 0, travel: 100), 0, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateOffset(at: 0.4, travel: 100), 50, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateOffset(at: 0.8, travel: 100), 100, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateOffset(at: 1.2, travel: 100), 50, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateWidth(at: 0, trackWidth: 200), 32, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateWidth(at: 0.4, trackWidth: 200), 80, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateWidth(at: 0.8, trackWidth: 200), 32, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateWidth(at: 1.2, trackWidth: 200), 80, accuracy: 0.001)
    }
}
