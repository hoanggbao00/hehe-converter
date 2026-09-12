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
        stripsMetadata: Bool
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
            arguments += ["-c:v", "png", "-compression_level", "9"]
        case "webp":
            arguments += ["-c:v", "libwebp", "-quality", "\(normalizedQuality(quality))"]
        case "avif":
            arguments += ["-c:v", "libaom-av1", "-crf", "\(avifCRF(for: quality))", "-still-picture", "1"]
        default:
            throw ImageCompressError.unsupportedFormat(fileExtension)
        }

        arguments += ["-frames:v", "1", "-y", outputURL.path]
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
}

enum ImageCompressFFmpegRunner {
    static func preview(
        inputURL: URL,
        quality: Double,
        stripsMetadata: Bool,
        fileManager: FileManager = .default
    ) async throws -> ImageCompressPreviewResult {
        guard let installation = FFmpegInstall.installation else {
            throw ImagePresetConversionError.ffmpegNotInstalled
        }

        let fileManager = CompressSendableFileManager(value: fileManager)
        let tempURL = try previewTempURL(for: inputURL, fileManager: fileManager.value)
        let arguments = try ImageCompressFFmpegCommandBuilder.arguments(
            inputURL: inputURL,
            outputURL: tempURL,
            quality: quality,
            stripsMetadata: stripsMetadata
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
        let arguments = try ImageCompressFFmpegCommandBuilder.arguments(
            inputURL: inputURL,
            outputURL: tempURL,
            quality: quality,
            stripsMetadata: stripsMetadata
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
