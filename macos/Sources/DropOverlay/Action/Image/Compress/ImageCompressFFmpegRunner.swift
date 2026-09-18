import Foundation
import ImageIO

private struct CompressSendableFileManager: @unchecked Sendable {
    let value: FileManager
}

struct ImageCompressResult: Sendable {
    let outputURL: URL
    let inputBytes: Int64
    let outputBytes: Int64

    var savedBytes: Int64 {
        max(0, inputBytes - outputBytes)
    }

    var savedPercent: Int {
        guard inputBytes > 0 else { return 0 }
        return max(0, Int((Double(savedBytes) / Double(inputBytes) * 100).rounded()))
    }
}

struct ImageCompressPreviewResult: Sendable {
    let thumbnail: CGImage?
    let outputBytes: Int64
}

enum ImageCompressError: LocalizedError {
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(fileExtension):
            "Compress does not support .\(fileExtension) images yet."
        }
    }
}

enum ImageCompressFFmpegCommandBuilder {
    // ponytail: V1 keeps source format; add output-format controls when compress also owns conversion.
    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "avif"]

    static func arguments(
        inputURL: URL,
        outputURL: URL,
        quality: Double,
        stripsMetadata: Bool,
        pngCompressionLevel: Int = 9,
        isAnimatedWebP: Bool = false,
        fps: Double? = nil
    ) throws -> [String] {
        let fileExtension = inputURL.pathExtension.lowercased()
        guard supportedExtensions.contains(fileExtension) else {
            throw ImageCompressError.unsupportedFormat(fileExtension)
        }

        var arguments = ["-i", inputURL.path]
        if stripsMetadata {
            arguments += ["-map_metadata", "-1"]
        }

        switch fileExtension {
        case "jpg", "jpeg":
            arguments += ["-c:v", "mjpeg", "-q:v", "\(jpegQScale(for: quality))"]
        case "png":
            arguments += ["-c:v", "png", "-compression_level", "\(min(max(pngCompressionLevel, 0), 9))"]
        case "webp":
            if isAnimatedWebP {
                if let fps {
                    arguments += ["-vf", "fps=\(decimal(min(max(fps, 1), 60)))"]
                }
                arguments += ["-an", "-c:v", "libwebp_anim", "-quality", "\(normalizedQuality(quality))", "-loop", "0"]
            } else {
                arguments += ["-c:v", "libwebp", "-quality", "\(normalizedQuality(quality))"]
            }
        case "avif":
            arguments += ["-c:v", "libaom-av1", "-crf", "\(avifCRF(for: quality))", "-still-picture", "1"]
        default:
            throw ImageCompressError.unsupportedFormat(fileExtension)
        }

        if !isAnimatedWebP {
            arguments += ["-frames:v", "1"]
        }
        arguments += ["-y", outputURL.path]
        return arguments
    }

    static func jpegQScale(for quality: Double) -> Int {
        let quality = min(max(quality, 1), 100)
        return Int((31 - quality / 100 * 29).rounded())
    }

    static func avifCRF(for quality: Double) -> Int {
        let quality = min(max(quality, 1), 100)
        return Int((63 * (100 - quality) / 99).rounded())
    }

    private static func normalizedQuality(_ quality: Double) -> Int {
        Int(min(max(quality, 1), 100).rounded())
    }

    private static func decimal(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        var string = String(format: "%.2f", rounded)
        while string.last == "0" { string.removeLast() }
        if string.last == "." { string.removeLast() }
        return string
    }
}

struct ImageCompressSourceMetadata: Sendable {
    let frameCount: Int
    let fps: Double?

    var isAnimatedWebP: Bool {
        frameCount > 1
    }
}

enum ImageCompressSourceInspector {
    static func metadata(for inputURL: URL) -> ImageCompressSourceMetadata {
        guard inputURL.pathExtension.lowercased() == "webp" else {
            return ImageCompressSourceMetadata(frameCount: 1, fps: nil)
        }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, sourceOptions) else {
            return ImageCompressSourceMetadata(frameCount: 1, fps: nil)
        }
        let frameCount = CGImageSourceGetCount(source)
        return ImageCompressSourceMetadata(
            frameCount: frameCount,
            fps: fps(for: source, frameCount: frameCount)
        )
    }

    private static func fps(for source: CGImageSource, frameCount: Int) -> Double? {
        guard frameCount > 1 else { return nil }

        var totalDelay = 0.0
        for index in 0..<frameCount {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let webp = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] else {
                continue
            }
            let delay = webp[kCGImagePropertyWebPUnclampedDelayTime] as? Double
                ?? webp[kCGImagePropertyWebPDelayTime] as? Double
                ?? 0
            totalDelay += delay
        }

        guard totalDelay > 0 else { return nil }
        return min(max(Double(frameCount) / totalDelay, 1), 60)
    }
}

enum ImageCompressFFmpegRunner {
    static func preview(
        inputURL: URL,
        quality: Double,
        stripsMetadata: Bool,
        pngCompressionLevel: Int = 9,
        fps: Double? = nil,
        fileManager: FileManager = .default
    ) async throws -> ImageCompressPreviewResult {
        guard let installation = FFmpegInstall.installation else {
            throw ImagePresetConversionError.ffmpegNotInstalled
        }

        let fileManager = CompressSendableFileManager(value: fileManager)
        let tempURL = try previewTempURL(for: inputURL, fileManager: fileManager.value)
        let metadata = ImageCompressSourceInspector.metadata(for: inputURL)
        let arguments = try ImageCompressFFmpegCommandBuilder.arguments(
            inputURL: inputURL,
            outputURL: tempURL,
            quality: quality,
            stripsMetadata: stripsMetadata,
            pngCompressionLevel: pngCompressionLevel,
            isAnimatedWebP: metadata.isAnimatedWebP,
            fps: fps ?? metadata.fps
        )

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = installation.ffmpegURL
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                defer { try? fileManager.value.removeItem(at: tempURL) }
                do {
                    guard process.terminationStatus == 0,
                          fileManager.value.fileExists(atPath: tempURL.path) else {
                        throw ImagePresetConversionError.commandFailed(process.terminationStatus)
                    }
                    continuation.resume(returning: ImageCompressPreviewResult(
                        thumbnail: previewThumbnail(at: tempURL),
                        outputBytes: fileSize(at: tempURL, fileManager: fileManager.value)
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                try? fileManager.value.removeItem(at: tempURL)
                continuation.resume(throwing: error)
            }
        }
    }

    static func run(
        inputURL: URL,
        quality: Double,
        stripsMetadata: Bool,
        pngCompressionLevel: Int = 9,
        fps: Double? = nil,
        fileManager: FileManager = .default
    ) async throws -> ImageCompressResult {
        guard let installation = FFmpegInstall.installation else {
            throw ImagePresetConversionError.ffmpegNotInstalled
        }

        let fileManager = CompressSendableFileManager(value: fileManager)
        let outputURL = availableOutputURL(for: inputURL, fileManager: fileManager)
        let tempURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".__hehecompressed-\(UUID().uuidString)")
            .appendingPathExtension(outputURL.pathExtension)
        let metadata = ImageCompressSourceInspector.metadata(for: inputURL)
        let arguments = try ImageCompressFFmpegCommandBuilder.arguments(
            inputURL: inputURL,
            outputURL: tempURL,
            quality: quality,
            stripsMetadata: stripsMetadata,
            pngCompressionLevel: pngCompressionLevel,
            isAnimatedWebP: metadata.isAnimatedWebP,
            fps: fps ?? metadata.fps
        )

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = installation.ffmpegURL
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                do {
                    guard process.terminationStatus == 0,
                          fileManager.value.fileExists(atPath: tempURL.path) else {
                        throw ImagePresetConversionError.commandFailed(process.terminationStatus)
                    }
                    let inputBytes = fileSize(at: inputURL, fileManager: fileManager.value)
                    let outputBytes = fileSize(at: tempURL, fileManager: fileManager.value)
                    try fileManager.value.moveItem(at: tempURL, to: outputURL)
                    continuation.resume(returning: ImageCompressResult(
                        outputURL: outputURL,
                        inputBytes: inputBytes,
                        outputBytes: outputBytes
                    ))
                } catch {
                    try? fileManager.value.removeItem(at: tempURL)
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                try? fileManager.value.removeItem(at: tempURL)
                continuation.resume(throwing: error)
            }
        }
    }

    private static func fileSize(at url: URL, fileManager: FileManager) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func previewThumbnail(at url: URL) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func previewTempURL(for inputURL: URL, fileManager: FileManager = .default) throws -> URL {
        let directory = AppConstants.managedTempURL
            .appendingPathComponent("compress-preview", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
            .appendingPathComponent(".__hehecompress-preview-\(UUID().uuidString)")
            .appendingPathExtension(inputURL.pathExtension)
    }

    private static func availableOutputURL(
        for inputURL: URL,
        fileManager: CompressSendableFileManager
    ) -> URL {
        availableOutputURL(for: inputURL, fileManager: fileManager.value)
    }

    static func availableOutputURL(for inputURL: URL, fileManager: FileManager = .default) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let basename = inputURL.deletingPathExtension().lastPathComponent
        let fileExtension = inputURL.pathExtension

        func candidate(_ suffix: Int?) -> URL {
            let name = suffix.map { "\(basename)-compressed-\($0)" } ?? "\(basename)-compressed"
            return directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
        }

        let first = candidate(nil)
        guard fileManager.fileExists(atPath: first.path) else { return first }

        var index = 1
        while true {
            let url = candidate(index)
            if !fileManager.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }
}
