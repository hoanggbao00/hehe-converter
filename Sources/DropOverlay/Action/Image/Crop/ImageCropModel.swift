import AppKit
import ImageIO
import SwiftUI

@MainActor
final class ImageCropModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var unit: CropDimensionUnit = .percent
    @Published var aspectRatio: CropAspectRatio = .freeform
    @Published private(set) var width = 100.0
    @Published private(set) var height = 100.0
    @Published var cropCenter = CGPoint(x: 0.5, y: 0.5)
    @Published var isApplying = false
    @Published private(set) var isLoadingImage = true
    @Published var errorMessage: String?

    let inputURL: URL
    @Published private(set) var pixelSize = CGSize(width: 960, height: 718)
    @Published private(set) var previewImage: NSImage?

    init(inputURL: URL) {
        self.inputURL = inputURL
    }

    func loadImage() async {
        guard isLoadingImage else { return }
        let sourceInfo = await Task.detached(priority: .userInitiated) { [inputURL] in
            Self.loadSourceInfo(inputURL: inputURL)
        }.value
        pixelSize = sourceInfo.pixelSize
        previewImage = sourceInfo.thumbnail.map { NSImage(cgImage: $0, size: .zero) }
        isLoadingImage = false
    }

    func reset() {
        unit = .percent
        aspectRatio = .freeform
        width = 100
        height = 100
        cropCenter = CGPoint(x: 0.5, y: 0.5)
        errorMessage = nil
    }

    func applyUnit(_ newUnit: CropDimensionUnit) {
        guard unit != newUnit else { return }
        if newUnit == .pixels {
            width = round(pixelSize.width * width / 100)
            height = round(pixelSize.height * height / 100)
        } else {
            width = round(width / pixelSize.width * 100)
            height = round(height / pixelSize.height * 100)
        }
        unit = newUnit
    }

    func applyAspectRatio(_ newRatio: CropAspectRatio) {
        aspectRatio = newRatio
        guard newRatio.ratio(for: pixelSize) != nil else { return }
        setWidth(width)
    }

    func setWidth(_ newWidth: Double) {
        setCropSize(widthPixels: pixels(for: newWidth, axis: .horizontal), changedAxis: .horizontal)
    }

    func setHeight(_ newHeight: Double) {
        setCropSize(heightPixels: pixels(for: newHeight, axis: .vertical), changedAxis: .vertical)
    }

    func moveCrop(from start: CGPoint, translation: CGSize) {
        let widthFraction = fraction(for: width, axis: .horizontal)
        let heightFraction = fraction(for: height, axis: .vertical)
        cropCenter = CGPoint(
            x: min(max(start.x + translation.width, widthFraction / 2), 1 - widthFraction / 2),
            y: min(max(start.y + translation.height, heightFraction / 2), 1 - heightFraction / 2)
        )
    }

    func resizeCrop(handle: CropHandlePosition, from startRect: CGRect, translation: CGSize) {
        let minimumSize: CGFloat = 0.03
        var minX = startRect.minX
        var maxX = startRect.maxX
        var minY = startRect.minY
        var maxY = startRect.maxY

        if handle.horizontalEdge < 0 {
            minX = min(max(startRect.minX + translation.width, 0), maxX - minimumSize)
        } else if handle.horizontalEdge > 0 {
            maxX = max(min(startRect.maxX + translation.width, 1), minX + minimumSize)
        }

        if handle.verticalEdge < 0 {
            minY = min(max(startRect.minY + translation.height, 0), maxY - minimumSize)
        } else if handle.verticalEdge > 0 {
            maxY = max(min(startRect.maxY + translation.height, 1), minY + minimumSize)
        }

        if let ratio = aspectRatio.ratio(for: pixelSize) {
            let prefersWidth = handle.verticalEdge == 0
                || (handle.horizontalEdge != 0 && abs(translation.width) * pixelSize.width >= abs(translation.height) * pixelSize.height)
            let widthFraction = maxX - minX
            let heightFraction = maxY - minY
            let ratioWidthFraction = heightFraction * pixelSize.height * ratio / pixelSize.width
            let ratioHeightFraction = widthFraction * pixelSize.width / ratio / pixelSize.height
            let fitted = fittedRect(
                widthFraction: prefersWidth ? widthFraction : ratioWidthFraction,
                heightFraction: prefersWidth ? ratioHeightFraction : heightFraction,
                handle: handle,
                startRect: startRect
            )
            minX = fitted.minX
            maxX = fitted.maxX
            minY = fitted.minY
            maxY = fitted.maxY
        }

        updateDimensions(widthFraction: maxX - minX, heightFraction: maxY - minY)
        cropCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    func cropRect(in imageRect: CGRect) -> CGRect {
        let widthFraction = fraction(for: width, axis: .horizontal)
        let heightFraction = fraction(for: height, axis: .vertical)
        let size = CGSize(
            width: imageRect.width * widthFraction,
            height: imageRect.height * heightFraction
        )
        let center = CGPoint(
            x: imageRect.minX + imageRect.width * cropCenter.x,
            y: imageRect.minY + imageRect.height * cropCenter.y
        )
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func normalizedCropRect() -> CGRect {
        let widthFraction = fraction(for: width, axis: .horizontal)
        let heightFraction = fraction(for: height, axis: .vertical)
        return CGRect(
            x: cropCenter.x - widthFraction / 2,
            y: cropCenter.y - heightFraction / 2,
            width: widthFraction,
            height: heightFraction
        )
    }

    func pixelCropRect() -> CGRect {
        let rect = normalizedCropRect()
        let x = max(0, min(pixelSize.width - 1, floor(rect.minX * pixelSize.width)))
        let y = max(0, min(pixelSize.height - 1, floor(rect.minY * pixelSize.height)))
        let maxWidth = pixelSize.width - x
        let maxHeight = pixelSize.height - y
        return CGRect(
            x: x,
            y: y,
            width: max(1, min(maxWidth, round(rect.width * pixelSize.width))),
            height: max(1, min(maxHeight, round(rect.height * pixelSize.height)))
        )
    }

    func previewSize(fitting maximumSize: CGSize) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return maximumSize }
        let scale = min(maximumSize.width / pixelSize.width, maximumSize.height / pixelSize.height)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    func applyCrop() async throws -> URL {
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        return try await ImageCropFFmpegRunner.run(inputURL: inputURL, cropRect: pixelCropRect())
    }

    nonisolated private static func loadSourceInfo(inputURL: URL) -> ImageCropSourceInfo {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, sourceOptions) else {
            return ImageCropSourceInfo(pixelSize: CGSize(width: 960, height: 718), thumbnail: nil)
        }
        let size = pixelSize(from: source) ?? CGSize(width: 960, height: 718)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return ImageCropSourceInfo(
            pixelSize: size,
            thumbnail: CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        )
    }

    nonisolated private static func pixelSize(from source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private func setCropSize(widthPixels: CGFloat? = nil, heightPixels: CGFloat? = nil, changedAxis: Axis) {
        var nextWidth = min(max(widthPixels ?? pixels(for: width, axis: .horizontal), 1), pixelSize.width)
        var nextHeight = min(max(heightPixels ?? pixels(for: height, axis: .vertical), 1), pixelSize.height)

        if let ratio = aspectRatio.ratio(for: pixelSize) {
            if changedAxis == .horizontal {
                nextHeight = nextWidth / ratio
                if nextHeight > pixelSize.height {
                    nextHeight = pixelSize.height
                    nextWidth = nextHeight * ratio
                }
            } else {
                nextWidth = nextHeight * ratio
                if nextWidth > pixelSize.width {
                    nextWidth = pixelSize.width
                    nextHeight = nextWidth / ratio
                }
            }
        }

        setDisplayedDimensions(widthPixels: nextWidth, heightPixels: nextHeight)
        clampCropCenter()
    }

    private func fittedRect(
        widthFraction: CGFloat,
        heightFraction: CGFloat,
        handle: CropHandlePosition,
        startRect: CGRect
    ) -> CGRect {
        var width = max(widthFraction, 0.03)
        var height = max(heightFraction, 0.03)
        let maxWidth = handle.horizontalEdge < 0
            ? startRect.maxX
            : handle.horizontalEdge > 0
                ? 1 - startRect.minX
                : 2 * min(startRect.midX, 1 - startRect.midX)
        let maxHeight = handle.verticalEdge < 0
            ? startRect.maxY
            : handle.verticalEdge > 0
                ? 1 - startRect.minY
                : 2 * min(startRect.midY, 1 - startRect.midY)
        let scale = min(1, maxWidth / width, maxHeight / height)
        width *= scale
        height *= scale

        let minX: CGFloat
        let maxX: CGFloat
        if handle.horizontalEdge < 0 {
            maxX = startRect.maxX
            minX = max(0, maxX - width)
        } else if handle.horizontalEdge > 0 {
            minX = startRect.minX
            maxX = min(1, minX + width)
        } else {
            minX = min(max(startRect.midX - width / 2, 0), 1 - width)
            maxX = minX + width
        }

        let minY: CGFloat
        let maxY: CGFloat
        if handle.verticalEdge < 0 {
            maxY = startRect.maxY
            minY = max(0, maxY - height)
        } else if handle.verticalEdge > 0 {
            minY = startRect.minY
            maxY = min(1, minY + height)
        } else {
            minY = min(max(startRect.midY - height / 2, 0), 1 - height)
            maxY = minY + height
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func updateDimensions(widthFraction: CGFloat, heightFraction: CGFloat) {
        setDisplayedDimensions(
            widthPixels: pixelSize.width * min(max(widthFraction, 0.01), 1),
            heightPixels: pixelSize.height * min(max(heightFraction, 0.01), 1)
        )
    }

    private func setDisplayedDimensions(widthPixels: CGFloat, heightPixels: CGFloat) {
        if unit == .percent {
            width = Double(widthPixels / pixelSize.width * 100)
            height = Double(heightPixels / pixelSize.height * 100)
        } else {
            width = Double(round(widthPixels))
            height = Double(round(heightPixels))
        }
    }

    private func fraction(for value: Double, axis: Axis) -> CGFloat {
        let pixelLength = axis == .horizontal ? pixelSize.width : pixelSize.height
        return min(max(unit == .percent ? CGFloat(value / 100) : CGFloat(value) / pixelLength, 0.01), 1)
    }

    private func pixels(for value: Double, axis: Axis) -> CGFloat {
        let pixelLength = axis == .horizontal ? pixelSize.width : pixelSize.height
        return unit == .percent ? pixelLength * CGFloat(value / 100) : CGFloat(value)
    }

    private func clampCropCenter() {
        let widthFraction = fraction(for: width, axis: .horizontal)
        let heightFraction = fraction(for: height, axis: .vertical)
        cropCenter = CGPoint(
            x: min(max(cropCenter.x, widthFraction / 2), 1 - widthFraction / 2),
            y: min(max(cropCenter.y, heightFraction / 2), 1 - heightFraction / 2)
        )
    }
}

private struct ImageCropSourceInfo: Sendable {
    let pixelSize: CGSize
    let thumbnail: CGImage?
}

enum CropAspectRatio: String, CaseIterable, Identifiable {
    case original = "Original"
    case freeform = "Freeform"
    case square = "1:1"
    case fourThree = "4:3"
    case threeFour = "3:4"
    case threeTwo = "3:2"
    case twoThree = "2:3"
    case sixteenNine = "16:9"
    case nineSixteen = "9:16"

    var id: Self { self }

    func ratio(for pixelSize: CGSize) -> CGFloat? {
        switch self {
        case .original: pixelSize.width / pixelSize.height
        case .freeform: nil
        case .square: 1
        case .fourThree: 4 / 3
        case .threeFour: 3 / 4
        case .threeTwo: 3 / 2
        case .twoThree: 2 / 3
        case .sixteenNine: 16 / 9
        case .nineSixteen: 9 / 16
        }
    }
}

enum CropDimensionUnit: String, CaseIterable, Identifiable {
    case percent = "%"
    case pixels = "px"

    var id: Self { self }

    func range(for pixelSize: CGSize, axis: Axis) -> ClosedRange<Double> {
        switch self {
        case .percent: return 1...100
        case .pixels:
            let maxValue = axis == .horizontal ? pixelSize.width : pixelSize.height
            return 1...max(1, maxValue)
        }
    }
}

enum CropHandlePosition: CaseIterable, Identifiable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var id: Self { self }

    var horizontalEdge: CGFloat {
        switch self {
        case .topLeft, .bottomLeft, .left: -1
        case .topRight, .bottomRight, .right: 1
        case .top, .bottom: 0
        }
    }

    var verticalEdge: CGFloat {
        switch self {
        case .topLeft, .top, .topRight: -1
        case .bottomLeft, .bottom, .bottomRight: 1
        case .left, .right: 0
        }
    }

    var isCorner: Bool {
        horizontalEdge != 0 && verticalEdge != 0
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

private extension NSImage {
    var pixelSize: CGSize {
        guard let representation = representations.first else { return size }
        return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }
}
