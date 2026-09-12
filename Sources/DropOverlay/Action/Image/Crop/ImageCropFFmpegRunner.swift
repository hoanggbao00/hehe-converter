import Foundation

private struct SendableFileManager: @unchecked Sendable {
    let value: FileManager
}

enum ImageCropFFmpegCommandBuilder {
    static func arguments(inputURL: URL, outputURL: URL, cropRect: CGRect) -> [String] {
        [
            "-i", inputURL.path,
            "-vf", "crop=\(Int(cropRect.width)):\(Int(cropRect.height)):\(Int(cropRect.minX)):\(Int(cropRect.minY))",
            "-frames:v", "1",
            "-y", outputURL.path
        ]
    }
}

enum ImageCropFFmpegRunner {
    static func run(inputURL: URL, cropRect: CGRect, fileManager: FileManager = .default) async throws -> URL {
        guard let installation = FFmpegInstall.installation else {
            throw ImagePresetConversionError.ffmpegNotInstalled
        }

        let fileManager = SendableFileManager(value: fileManager)
        let outputURL = availableOutputURL(for: inputURL, fileManager: fileManager)
        let tempURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".__hehecrop-\(UUID().uuidString)")
            .appendingPathExtension(outputURL.pathExtension)

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = installation.ffmpegURL
            process.arguments = ImageCropFFmpegCommandBuilder.arguments(inputURL: inputURL, outputURL: tempURL, cropRect: cropRect)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                do {
                    guard process.terminationStatus == 0 else {
                        throw ImagePresetConversionError.commandFailed(process.terminationStatus)
                    }
                    guard fileManager.value.fileExists(atPath: tempURL.path) else {
                        throw ImagePresetConversionError.commandFailed(process.terminationStatus)
                    }
                    try fileManager.value.moveItem(at: tempURL, to: outputURL)
                    continuation.resume(returning: outputURL)
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

    private static func availableOutputURL(for inputURL: URL, fileManager: SendableFileManager) -> URL {
        availableOutputURL(for: inputURL, fileManager: fileManager.value)
    }

    static func availableOutputURL(for inputURL: URL, fileManager: FileManager = .default) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let basename = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension.isEmpty ? "png" : inputURL.pathExtension

        func candidate(_ suffix: Int?) -> URL {
            let name = suffix.map { "\(basename)-cropped-\($0)" } ?? "\(basename)-cropped"
            return directory.appendingPathComponent(name).appendingPathExtension(ext)
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
