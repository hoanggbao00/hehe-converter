import Foundation

private struct VideoCropSendableFileManager: @unchecked Sendable {
    let value: FileManager
}

enum VideoCropFFmpegCommandBuilder {
    static func arguments(inputURL: URL, outputURL: URL, cropRect: CGRect) -> [String] {
        var arguments = [
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-vf", "crop=\(Int(cropRect.width)):\(Int(cropRect.height)):\(Int(cropRect.minX)):\(Int(cropRect.minY))"
        ]
        if outputURL.pathExtension.lowercased() == "webm" {
            arguments += ["-c:v", "libvpx-vp9", "-c:a", "copy"]
        } else {
            arguments += ["-c:v", "libx264", "-c:a", "copy"]
        }
        arguments += ["-y", outputURL.path]
        return arguments
    }
}

enum VideoCropFFmpegRunner {
    static func run(inputURL: URL, cropRect: CGRect, fileManager: FileManager = .default) async throws -> URL {
        guard let installation = FFmpegInstall.installation else {
            throw ImagePresetConversionError.ffmpegNotInstalled
        }

        let fileManager = VideoCropSendableFileManager(value: fileManager)
        let outputURL = availableOutputURL(for: inputURL, fileManager: fileManager.value)
        let tempURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".__hehe-video-crop-\(UUID().uuidString)")
            .appendingPathExtension(outputURL.pathExtension)

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = installation.ffmpegURL
            process.arguments = VideoCropFFmpegCommandBuilder.arguments(
                inputURL: inputURL,
                outputURL: tempURL,
                cropRect: cropRect
            )
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                do {
                    guard process.terminationStatus == 0,
                          fileManager.value.fileExists(atPath: tempURL.path) else {
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

    static func availableOutputURL(for inputURL: URL, fileManager: FileManager = .default) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let basename = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension.isEmpty ? "mp4" : inputURL.pathExtension

        func candidate(_ suffix: Int?) -> URL {
            let name = suffix.map { "\(basename)-cropped-\($0)" } ?? "\(basename)-cropped"
            return directory.appendingPathComponent(name).appendingPathExtension(ext)
        }

        let first = candidate(nil)
        guard fileManager.fileExists(atPath: first.path) else { return first }
        var index = 1
        while fileManager.fileExists(atPath: candidate(index).path) { index += 1 }
        return candidate(index)
    }
}
