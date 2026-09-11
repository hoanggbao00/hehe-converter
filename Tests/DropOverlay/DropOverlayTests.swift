import XCTest
@testable import HeheConverter

final class DropOverlayTests: XCTestCase {
    func testImageActionsKeepReferenceOrderAndIcons() {
        XCTAssertEqual(ImageAction.allCases, [.resize, .crop, .compress])
        XCTAssertEqual(ImageAction.resize.systemImage, "aspectratio")
        XCTAssertEqual(ImageAction.crop.systemImage, "crop")
        XCTAssertEqual(ImageAction.compress.systemImage, "arrow.down.right.and.arrow.up.left")
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
