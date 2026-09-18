import AppKit
import ImageIO
import SwiftUI

struct ImageCompressSettings: Equatable {
    let quality: Double
    let stripsMetadata: Bool
    let pngCompressionLevel: Int
    let fps: Double?
}

@MainActor
final class ImageCompressModel: ObservableObject, Identifiable {
    let id = UUID()
    let inputURL: URL

    @Published var quality = 80.0
    @Published var pngCompressionLevel = 9.0
    @Published var fps = 24.0
    @Published var stripsMetadata = true
    @Published var isApplying = false
    @Published private(set) var isLoadingImage = true
    @Published private(set) var isLoadingPreview = false
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var compressedPreviewImage: NSImage?
    @Published private(set) var pixelSize = CGSize.zero
    @Published private(set) var inputBytes: Int64 = 0
    @Published private(set) var previewBytes: Int64?
    @Published private(set) var frameCount = 1
    @Published var errorMessage: String?
    private var previewGeneration = 0

    init(inputURL: URL) {
        self.inputURL = inputURL
        let metadata = ImageCompressSourceInspector.metadata(for: inputURL)
        frameCount = metadata.frameCount
        fps = metadata.fps ?? fps
    }

    var settings: ImageCompressSettings {
        ImageCompressSettings(
            quality: quality,
            stripsMetadata: stripsMetadata,
            pngCompressionLevel: Int(pngCompressionLevel.rounded()),
            fps: supportsFPS ? fps : nil
        )
    }

    var supportsQuality: Bool {
        inputURL.pathExtension.lowercased() != "png"
    }

    var supportsFPS: Bool {
        inputURL.pathExtension.lowercased() == "webp" && frameCount > 1
    }

    var isSupported: Bool {
        ImageCompressFFmpegCommandBuilder.supportedExtensions.contains(inputURL.pathExtension.lowercased())
    }

    var formattedInputSize: String {
        ByteCountFormatter.string(fromByteCount: inputBytes, countStyle: .file)
    }

    var formattedPreviewSize: String? {
        previewBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    func previewSize(fitting maximumSize: CGSize) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return maximumSize }
        let scale = min(maximumSize.width / pixelSize.width, maximumSize.height / pixelSize.height)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    func reset() {
        quality = 80
        pngCompressionLevel = 9
        fps = 24
        stripsMetadata = true
        errorMessage = nil
        requestPreview()
    }

    func setStripsMetadata(_ value: Bool) {
        stripsMetadata = value
        requestPreview()
    }

    func requestPreview() {
        guard isSupported, !isLoadingImage else { return }
        previewGeneration += 1
        let generation = previewGeneration
        let settings = settings
        previewBytes = nil
        isLoadingPreview = true
        errorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await ImageCompressFFmpegRunner.preview(
                    inputURL: inputURL,
                    quality: settings.quality,
                    stripsMetadata: settings.stripsMetadata,
                    pngCompressionLevel: settings.pngCompressionLevel,
                    fps: settings.fps
                )
                guard generation == previewGeneration else { return }
                compressedPreviewImage = result.thumbnail.map { NSImage(cgImage: $0, size: .zero) }
                previewBytes = result.outputBytes
                isLoadingPreview = false
            } catch {
                guard generation == previewGeneration else { return }
                errorMessage = error.localizedDescription
                isLoadingPreview = false
            }
        }
    }

    func applyCompress() async throws -> ImageCompressResult {
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        return try await ImageCompressFFmpegRunner.run(
            inputURL: inputURL,
            quality: quality,
            stripsMetadata: stripsMetadata,
            pngCompressionLevel: Int(pngCompressionLevel.rounded()),
            fps: supportsFPS ? fps : nil
        )
    }

    func loadImage() async {
        guard isLoadingImage else { return }
        let sourceInfo = await Task.detached(priority: .userInitiated) { [inputURL] in
            Self.loadSourceInfo(inputURL: inputURL)
        }.value
        pixelSize = sourceInfo.pixelSize
        inputBytes = sourceInfo.inputBytes
        frameCount = sourceInfo.metadata.frameCount
        fps = sourceInfo.metadata.fps ?? fps
        previewImage = sourceInfo.thumbnail.map { NSImage(cgImage: $0, size: .zero) }
        isLoadingImage = false
        requestPreview()
    }

    nonisolated private static func loadSourceInfo(inputURL: URL) -> ImageCompressSourceInfo {
        let attributes = try? FileManager.default.attributesOfItem(atPath: inputURL.path)
        let inputBytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, sourceOptions) else {
            return ImageCompressSourceInfo(
                pixelSize: .zero,
                inputBytes: inputBytes,
                metadata: ImageCompressSourceMetadata(frameCount: 1, fps: nil),
                thumbnail: nil
            )
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return ImageCompressSourceInfo(
            pixelSize: CGSize(width: width, height: height),
            inputBytes: inputBytes,
            metadata: ImageCompressSourceInspector.metadata(for: inputURL),
            thumbnail: CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        )
    }
}

private struct ImageCompressSourceInfo: Sendable {
    let pixelSize: CGSize
    let inputBytes: Int64
    let metadata: ImageCompressSourceMetadata
    let thumbnail: CGImage?
}
