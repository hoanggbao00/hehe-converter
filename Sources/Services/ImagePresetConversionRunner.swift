import Foundation

enum ImagePresetConversionRunner {
    static func runBatch(
        preset: ImagePreset,
        inputURLs: [URL],
        mode: MultipleFileConversionMode = .sequential,
        maxConcurrentConversions: Int = 2,
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        if mode == .parallel, inputURLs.count > 1 {
            await runParallelBatch(
                preset: preset,
                inputURLs: inputURLs,
                maxConcurrentConversions: maxConcurrentConversions,
                update: update
            )
            return
        }

        let total = inputURLs.count
        var saved = 0
        var failed = 0

        for inputURL in inputURLs {
            if Task.isCancelled { break }
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
                ),
                isIndeterminate: true
            ))

            await ConversionLimiter.shared.acquire(limit: maxConcurrentConversions)
            if Task.isCancelled {
                await ConversionLimiter.shared.release()
                break
            }
            do {
                try await run(preset: preset, inputURL: inputURL, outputURL: outputURL)
                await ConversionLimiter.shared.release()
                saved += 1
            } catch {
                await ConversionLimiter.shared.release()
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: outputURL)
                    break
                }
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

    private static func runParallelBatch(
        preset: ImagePreset,
        inputURLs: [URL],
        maxConcurrentConversions: Int,
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        let total = inputURLs.count
        var saved = 0
        var failed = 0
        update(.init(state: .running, progress: 0, subtitle: "0 of \(total) saved", isIndeterminate: true))
        let jobs = reservedOutputURLs(
            for: inputURLs,
            outputExtension: preset.outputFormat.fileExtension
        )

        await withTaskGroup(of: Bool.self) { group in
            for (inputURL, outputURL) in jobs {
                group.addTask {
                    if Task.isCancelled { return false }
                    await ConversionLimiter.shared.acquire(limit: maxConcurrentConversions)
                    if Task.isCancelled {
                        await ConversionLimiter.shared.release()
                        return false
                    }
                    do {
                        try await run(preset: preset, inputURL: inputURL, outputURL: outputURL)
                        await ConversionLimiter.shared.release()
                        return true
                    } catch {
                        await ConversionLimiter.shared.release()
                        if Task.isCancelled {
                            try? FileManager.default.removeItem(at: outputURL)
                        }
                        return false
                    }
                }
            }

            for await succeeded in group {
                if succeeded { saved += 1 } else { failed += 1 }
                update(.init(
                    state: .running,
                    progress: Double(saved + failed) / Double(total),
                    subtitle: progressSubtitle(total: total, saved: saved, failed: failed)
                ))
            }
        }

        update(.init(
            state: failed == 0 ? .finished : .failed,
            progress: 1,
            subtitle: progressSubtitle(total: total, saved: saved, failed: failed)
        ))
    }

    static func reservedOutputURLs(
        for inputURLs: [URL],
        outputExtension: String,
        fileManager: FileManager = .default
    ) -> [(inputURL: URL, outputURL: URL)] {
        var reservedPaths = Set<String>()
        return inputURLs.map { inputURL in
            let outputURL = availableOutputURL(
                for: inputURL,
                outputExtension: outputExtension,
                fileManager: fileManager,
                reservedPaths: reservedPaths
            )
            reservedPaths.insert(outputURL.path)
            return (inputURL, outputURL)
        }
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

    static func run(preset: ImagePreset, inputURL: URL, outputURL: URL) async throws {
        guard let installation = FFmpegInstall.installation else {
            throw ImagePresetConversionError.ffmpegNotInstalled
        }

        let preparedInputURL = try await preparedInputURL(for: inputURL)
        defer {
            if preparedInputURL != inputURL {
                try? FileManager.default.removeItem(at: preparedInputURL.deletingLastPathComponent())
            }
        }

        let process = Process()
        process.executableURL = installation.ffmpegURL
        process.arguments = ImageFFmpegCommandBuilder.arguments(
            outputFormat: preset.outputFormat,
            resize: preset.resize,
            options: preset.options,
            inputURL: preparedInputURL,
            outputURL: outputURL
        )
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try await withTaskCancellationHandler {
            try process.run()
            process.waitUntilExit()
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        if Task.isCancelled {
            throw CancellationError()
        }

        guard process.terminationStatus == 0 else {
            throw ImagePresetConversionError.commandFailed(process.terminationStatus)
        }
    }

    static func preparedInputURL(for inputURL: URL) async throws -> URL {
        guard inputURL.pathExtension.caseInsensitiveCompare("svg") == .orderedSame else {
            return inputURL
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaDrop-SVG-\(UUID().uuidString)", isDirectory: true)
        let outputURL = directory
            .appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("png")
        try await SVGImageRasterizer.rasterize(inputURL: inputURL, outputURL: outputURL)
        return outputURL
    }

    static func availableOutputURL(
        for inputURL: URL,
        outputExtension: String,
        fileManager: FileManager = .default,
        reservedPaths: Set<String> = []
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
        guard fileManager.fileExists(atPath: first.path) || reservedPaths.contains(first.path) else {
            return first
        }

        var index = 1
        while true {
            let url = candidate(index)
            if !fileManager.fileExists(atPath: url.path), !reservedPaths.contains(url.path) {
                return url
            }
            index += 1
        }
    }
}

actor ConversionLimiter {
    static let shared = ConversionLimiter()

    private var activeCount = 0
    private var waiters: [(limit: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func acquire(limit: Int) async {
        let limit = max(1, limit)
        guard activeCount >= limit else {
            activeCount += 1
            return
        }
        await withCheckedContinuation { waiters.append((limit, $0)) }
    }

    func release() {
        activeCount = max(0, activeCount - 1)
        guard let index = waiters.firstIndex(where: { activeCount < $0.limit }) else {
            return
        }
        activeCount += 1
        waiters.remove(at: index).continuation.resume()
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
    var isIndeterminate = false
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
