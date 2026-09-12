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
    @Published private(set) var isLoadingPreviewSize = false
    @Published var errorMessage: String?

    let inputURL: URL
    @Published private(set) var pixelSize = CGSize(width: 960, height: 718)
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var inputBytes: Int64 = 0
    @Published private(set) var previewBytes: Int64?
    private var previewGeneration = 0
    private var lockedAspectRatio: Double?

    init(inputURL: URL) {
        self.inputURL = inputURL
    }

    var outputPixelSize: CGSize {
        Self.outputPixelSize(for: pixelSize, settings: settings)
    }

    var settings: ImageResizeSettings {
        ImageResizeSettings(unit: unit, width: width, height: height)
    }

    var formattedInputSize: String {
        ByteCountFormatter.string(fromByteCount: inputBytes, countStyle: .file)
    }

    var formattedPreviewSize: String {
        guard let previewBytes else { return isLoadingPreviewSize ? "Calculating..." : formattedInputSize }
        return ByteCountFormatter.string(fromByteCount: previewBytes, countStyle: .file)
    }

    nonisolated static func outputPixelSize(for sourcePixelSize: CGSize, settings: ImageResizeSettings) -> CGSize {
        guard sourcePixelSize.width > 0, sourcePixelSize.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        let boundingSize: CGSize
        switch settings.unit {
        case .percent:
            boundingSize = CGSize(
                width: max(1, round(sourcePixelSize.width * settings.width / 100)),
                height: max(1, round(sourcePixelSize.height * settings.height / 100))
            )
        case .pixels:
            boundingSize = CGSize(width: max(1, round(settings.width)), height: max(1, round(settings.height)))
        }
        return boundingSize
    }

    func reset() {
        unit = .percent
        width = 100
        height = 100
        keepsAspectRatio = true
        lockedAspectRatio = nil
        errorMessage = nil
        requestPreviewSize()
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
            height = clamped(
                width * pixelSize.width / pixelSize.height / aspectRatio,
                axis: .vertical
            )
        case .pixels:
            height = clamped(width / aspectRatio, axis: .vertical)
        }
    }

    func setHeight(_ newHeight: Double) {
        height = clamped(newHeight, axis: .vertical)
        guard keepsAspectRatio else { return }
        switch unit {
        case .percent:
            width = clamped(
                height * pixelSize.height / pixelSize.width * aspectRatio,
                axis: .horizontal
            )
        case .pixels:
            width = clamped(height * aspectRatio, axis: .horizontal)
        }
    }

    func setKeepsAspectRatio(_ isLocked: Bool) {
        guard keepsAspectRatio != isLocked else { return }
        if isLocked { lockedAspectRatio = currentAspectRatio }
        keepsAspectRatio = isLocked
        requestPreviewSize()
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
        return try await ImageResizeFFmpegRunner.run(
            inputURL: inputURL,
            outputPixelSize: outputPixelSize
        )
    }

    func requestPreviewSize() {
        guard !isLoadingImage else { return }
        previewGeneration += 1
        let generation = previewGeneration
        let outputPixelSize = outputPixelSize
        previewBytes = nil
        isLoadingPreviewSize = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let bytes = try await ImageResizeFFmpegRunner.previewSize(
                    inputURL: inputURL,
                    outputPixelSize: outputPixelSize
                )
                guard generation == previewGeneration else { return }
                previewBytes = bytes
                isLoadingPreviewSize = false
            } catch {
                guard generation == previewGeneration else { return }
                errorMessage = error.localizedDescription
                isLoadingPreviewSize = false
            }
        }
    }

    func loadImage() async {
        guard isLoadingImage else { return }
        let sourceInfo = await Task.detached(priority: .userInitiated) { [inputURL] in
            Self.loadSourceInfo(inputURL: inputURL)
        }.value
        pixelSize = sourceInfo.pixelSize
        inputBytes = sourceInfo.inputBytes
        previewImage = sourceInfo.thumbnail.map { NSImage(cgImage: $0, size: .zero) }
        isLoadingImage = false
        requestPreviewSize()
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

    private var aspectRatio: Double {
        lockedAspectRatio ?? max(pixelSize.width, 1) / max(pixelSize.height, 1)
    }

    private var currentAspectRatio: Double {
        let size = outputPixelSize
        return max(size.width, 1) / max(size.height, 1)
    }

    nonisolated private static func loadSourceInfo(inputURL: URL) -> ImageResizeSourceInfo {
        let attributes = try? FileManager.default.attributesOfItem(atPath: inputURL.path)
        let inputBytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, sourceOptions) else {
            return ImageResizeSourceInfo(pixelSize: CGSize(width: 960, height: 718), inputBytes: inputBytes, thumbnail: nil)
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
            inputBytes: inputBytes,
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
    let inputBytes: Int64
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
