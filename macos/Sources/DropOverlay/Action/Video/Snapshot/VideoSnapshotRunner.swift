import AVFoundation
import AppKit

private struct VideoSnapshotSendableFileManager: @unchecked Sendable {
    let value: FileManager
}

private final class VideoSnapshotSendableImageGenerator: @unchecked Sendable {
    let value: AVAssetImageGenerator

    init(value: AVAssetImageGenerator) {
        self.value = value
    }
}

enum VideoSnapshotRunner {
    static func run(
        inputURL: URL,
        time: Double,
        format: VideoSnapshotFormat,
        fileManager: FileManager = .default
    ) async throws -> URL {
        let fileManager = VideoSnapshotSendableFileManager(value: fileManager)
        let outputURL = availableOutputURL(for: inputURL, time: time, format: format, fileManager: fileManager.value)
        let tempURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".__hehe-video-snapshot-\(UUID().uuidString)")
            .appendingPathExtension(format.fileExtension)
        let image = try await image(inputURL: inputURL, time: time)
        guard let data = NSBitmapImageRep(cgImage: image).representation(
            using: format.bitmapFileType,
            properties: format.bitmapProperties
        ) else {
            throw VideoSnapshotRunnerError.encodingFailed
        }
        do {
            try data.write(to: tempURL, options: .atomic)
            if fileManager.value.fileExists(atPath: outputURL.path) {
                try fileManager.value.removeItem(at: tempURL)
                throw CocoaError(.fileWriteFileExists)
            }
            try fileManager.value.moveItem(at: tempURL, to: outputURL)
            return outputURL
        } catch {
            try? fileManager.value.removeItem(at: tempURL)
            throw error
        }
    }

    static func availableOutputURL(
        for inputURL: URL,
        time: Double,
        format: VideoSnapshotFormat,
        fileManager: FileManager = .default
    ) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let basename = inputURL.deletingPathExtension().lastPathComponent
        let timestamp = timestampSuffix(for: time)

        func candidate(_ suffix: Int?) -> URL {
            let name = suffix.map { "\(basename)-snapshot-\(timestamp)-\($0)" } ?? "\(basename)-snapshot-\(timestamp)"
            return directory.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
        }

        let first = candidate(nil)
        guard fileManager.fileExists(atPath: first.path) else { return first }
        var index = 1
        while fileManager.fileExists(atPath: candidate(index).path) { index += 1 }
        return candidate(index)
    }

    private static func image(inputURL: URL, time: Double) async throws -> CGImage {
        let asset = AVURLAsset(url: inputURL)
        let generator = VideoSnapshotSendableImageGenerator(value: AVAssetImageGenerator(asset: asset))
        generator.value.appliesPreferredTrackTransform = true
        generator.value.requestedTimeToleranceBefore = .zero
        generator.value.requestedTimeToleranceAfter = .zero
        let requestedTime = CMTime(seconds: max(0, time), preferredTimescale: 600)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                generator.value.generateCGImagesAsynchronously(forTimes: [NSValue(time: requestedTime)]) { _, image, _, result, error in
                    switch result {
                    case .succeeded:
                        if let image {
                            continuation.resume(returning: image)
                        } else {
                            continuation.resume(throwing: VideoSnapshotRunnerError.imageMissing)
                        }
                    case .failed:
                        continuation.resume(throwing: error ?? VideoSnapshotRunnerError.imageMissing)
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    @unknown default:
                        continuation.resume(throwing: VideoSnapshotRunnerError.imageMissing)
                    }
                }
            }
        } onCancel: {
            generator.value.cancelAllCGImageGeneration()
        }
    }

    private static func timestampSuffix(for time: Double) -> String {
        let seconds = max(0, Int(time.rounded(.down)))
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d-%02d-%02d", hours, minutes, remainingSeconds)
    }
}

private enum VideoSnapshotRunnerError: LocalizedError {
    case imageMissing
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .imageMissing: "Snapshot image could not be generated."
        case .encodingFailed: "Snapshot image could not be encoded."
        }
    }
}
