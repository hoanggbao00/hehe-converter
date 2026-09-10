import Foundation

enum ImagePresetConversionRunner {
    static func runBatch(
        preset: ImagePreset,
        inputURLs: [URL],
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        let total = inputURLs.count
        var saved = 0
        var failed = 0

        for inputURL in inputURLs {
            let outputURL = availableOutputURL(
                for: inputURL,
                outputExtension: preset.outputFormat.fileExtension
            )
            update(.init(
                state: .running,
                progress: Double(saved + failed) / Double(max(total, 1)),
                subtitle: progressSubtitle(
                    total: total,
                    saved: saved,
                    failed: failed,
                    outputFilename: outputURL.lastPathComponent
                )
            ))

            do {
                try await Task.detached(priority: .userInitiated) {
                    try run(preset: preset, inputURL: inputURL, outputURL: outputURL)
                }.value
                saved += 1
            } catch {
                failed += 1
            }

            update(.init(
                state: .running,
                progress: Double(saved + failed) / Double(max(total, 1)),
                subtitle: progressSubtitle(
                    total: total,
                    saved: saved,
                    failed: failed,
                    outputFilename: outputURL.lastPathComponent
                )
            ))
        }

        update(.init(
            state: failed == 0 ? .finished : .failed,
            progress: 1,
            subtitle: progressSubtitle(total: total, saved: saved, failed: failed)
        ))
    }

    static func progressSubtitle(
        total: Int,
        saved: Int,
        failed: Int,
        outputFilename: String? = nil
    ) -> String {
        if total == 1 {
            return outputFilename ?? (failed > 0 ? "Failed" : "Saved")
        }

        let savedText = "\(saved) of \(total) saved"
        return failed > 0 ? "\(savedText), \(failed) failed" : savedText
    }

    static func run(preset: ImagePreset, inputURL: URL, outputURL: URL) throws {
        guard let installation = FFmpegInstall.installation else {
            throw ImagePresetConversionError.ffmpegNotInstalled
        }

        let process = Process()
        process.executableURL = installation.ffmpegURL
        process.arguments = ImageFFmpegCommandBuilder.arguments(
            outputFormat: preset.outputFormat,
            resize: preset.resize,
            options: preset.options,
            inputURL: inputURL,
            outputURL: outputURL
        )
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ImagePresetConversionError.commandFailed(process.terminationStatus)
        }
    }

    static func availableOutputURL(
        for inputURL: URL,
        outputExtension: String,
        fileManager: FileManager = .default
    ) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let basename = inputURL.deletingPathExtension().lastPathComponent
        let normalizedExtension = outputExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        func candidate(_ suffix: Int?) -> URL {
            let name = suffix.map { "\(basename)-\($0)" } ?? basename
            return directory
                .appendingPathComponent(name)
                .appendingPathExtension(normalizedExtension)
        }

        let first = candidate(nil)
        guard fileManager.fileExists(atPath: first.path) else { return first }

        var index = 1
        while true {
            let url = candidate(index)
            if !fileManager.fileExists(atPath: url.path) {
                return url
            }
            index += 1
        }
    }
}

struct ImagePresetConversionUpdate: Sendable {
    enum State: Sendable {
        case running
        case finished
        case failed
    }

    let state: State
    let progress: Double
    let subtitle: String
}

enum ImagePresetConversionError: LocalizedError {
    case ffmpegNotInstalled
    case commandFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotInstalled:
            "ffmpeg is not installed."
        case let .commandFailed(status):
            "ffmpeg exited with status \(status)."
        }
    }
}
