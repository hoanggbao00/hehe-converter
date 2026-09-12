import AppKit
import ImageIO
import SwiftUI

struct ImageResizeSettings: Equatable {
    let unit: ImageDimensionUnit
    let width: Double
    let height: Double
}

@MainActor
final class ImageResizeModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var unit: ImageDimensionUnit = .percent
    @Published private(set) var width = 100.0
    @Published private(set) var height = 100.0
    @Published var keepsAspectRatio = true
    @Published var isApplying = false
    @Published private(set) var isLoadingImage = true
    @Published var errorMessage: String?

    let inputURL: URL
    @Published private(set) var pixelSize = CGSize(width: 960, height: 718)
    @Published private(set) var previewImage: NSImage?

    init(inputURL: URL) {
        self.inputURL = inputURL
    }

    var outputPixelSize: CGSize {
        Self.outputPixelSize(for: pixelSize, settings: settings)
    }

    var settings: ImageResizeSettings {
        ImageResizeSettings(unit: unit, width: width, height: height)
    }

    static func outputPixelSize(for sourcePixelSize: CGSize, settings: ImageResizeSettings) -> CGSize {
        switch settings.unit {
        case .percent:
            return CGSize(
                width: max(1, round(sourcePixelSize.width * settings.width / 100)),
                height: max(1, round(sourcePixelSize.height * settings.height / 100))
            )
        case .pixels:
            return CGSize(width: max(1, round(settings.width)), height: max(1, round(settings.height)))
        }
    }

    func reset() {
        unit = .percent
        width = 100
        height = 100
        keepsAspectRatio = true
        errorMessage = nil
    }

    func applyUnit(_ newUnit: ImageDimensionUnit) {
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

    func setWidth(_ newWidth: Double) {
        width = clamped(newWidth, axis: .horizontal)
        guard keepsAspectRatio else { return }
        switch unit {
        case .percent:
            height = width
        case .pixels:
            height = clamped(width * pixelSize.height / pixelSize.width, axis: .vertical)
        }
    }

    func setHeight(_ newHeight: Double) {
        height = clamped(newHeight, axis: .vertical)
        guard keepsAspectRatio else { return }
        switch unit {
        case .percent:
            width = height
        case .pixels:
            width = clamped(height * pixelSize.width / pixelSize.height, axis: .horizontal)
        }
    }

    func setKeepsAspectRatio(_ isLocked: Bool) {
        keepsAspectRatio = isLocked
        if isLocked {
            setWidth(width)
        }
    }

    func resizePreview(handle: ResizeHandlePosition, from startSize: CGSize, translation: CGSize, in imageRectSize: CGSize) {
        guard imageRectSize.width > 0, imageRectSize.height > 0 else { return }
        let widthDelta = Double(handle.horizontalEdge * translation.width / imageRectSize.width * pixelSize.width)
        let heightDelta = Double(handle.verticalEdge * translation.height / imageRectSize.height * pixelSize.height)
        let nextWidth = Double(startSize.width) + widthDelta
        let nextHeight = Double(startSize.height) + heightDelta

        if keepsAspectRatio {
            if abs(widthDelta) >= abs(heightDelta) {
                setWidth(value(forPixels: nextWidth, axis: .horizontal))
            } else {
                setHeight(value(forPixels: nextHeight, axis: .vertical))
            }
            return
        }

        width = clamped(value(forPixels: nextWidth, axis: .horizontal), axis: .horizontal)
        height = clamped(value(forPixels: nextHeight, axis: .vertical), axis: .vertical)
    }

    func previewRect(in imageRect: CGRect) -> CGRect {
        let output = outputPixelSize
        let widthFraction = min(max(output.width / max(pixelSize.width, 1), 0.01), 1)
        let heightFraction = min(max(output.height / max(pixelSize.height, 1), 0.01), 1)
        let size = CGSize(width: imageRect.width * widthFraction, height: imageRect.height * heightFraction)
        return CGRect(
            x: imageRect.midX - size.width / 2,
            y: imageRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func range(for axis: Axis) -> ClosedRange<Double> {
        switch unit {
        case .percent:
            1...100
        case .pixels:
            1...32_768
        }
    }

    func previewSize(fitting maximumSize: CGSize) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return maximumSize }
        let scale = min(maximumSize.width / pixelSize.width, maximumSize.height / pixelSize.height)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    func applyResize() async throws -> URL {
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        return try await ImageResizeFFmpegRunner.run(inputURL: inputURL, outputPixelSize: outputPixelSize)
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

    private func clamped(_ value: Double, axis: Axis) -> Double {
        let range = range(for: axis)
        return min(max(value.rounded(), range.lowerBound), range.upperBound)
    }

    private func value(forPixels pixels: Double, axis: Axis) -> Double {
        switch unit {
        case .percent:
            let length = axis == .horizontal ? pixelSize.width : pixelSize.height
            return pixels / max(length, 1) * 100
        case .pixels:
            return pixels
        }
    }

    nonisolated private static func loadSourceInfo(inputURL: URL) -> ImageResizeSourceInfo {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, sourceOptions) else {
            return ImageResizeSourceInfo(pixelSize: CGSize(width: 960, height: 718), thumbnail: nil)
        }
        let size = pixelSize(from: source) ?? CGSize(width: 960, height: 718)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return ImageResizeSourceInfo(
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
}

private struct ImageResizeSourceInfo: Sendable {
    let pixelSize: CGSize
    let thumbnail: CGImage?
}

enum ResizeHandlePosition: CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    var id: Self { self }

    var horizontalEdge: CGFloat {
        switch self {
        case .topLeft, .bottomLeft: -1
        case .topRight, .bottomRight: 1
        }
    }

    var verticalEdge: CGFloat {
        switch self {
        case .topLeft, .topRight: -1
        case .bottomRight, .bottomLeft: 1
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        }
    }
}
