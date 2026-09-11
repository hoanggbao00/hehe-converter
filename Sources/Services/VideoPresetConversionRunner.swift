import Foundation

enum VideoPresetConversionRunner {
    static func runBatch(
        preset: VideoPreset,
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
            let outputURL = ImagePresetConversionRunner.availableOutputURL(
                for: inputURL,
                outputExtension: preset.outputFormat.fileExtension
            )
            update(.init(
                state: .running,
                progress: Double(saved + failed) / Double(max(total, 1)),
                subtitle: ImagePresetConversionRunner.progressSubtitle(
                    total: total,
                    saved: saved,
                    failed: failed,
                    outputFilename: outputURL.lastPathComponent
                ),
                isIndeterminate: true
            ))

            let completedBeforeFile = saved + failed
            let savedBeforeFile = saved
            let failedBeforeFile = failed
            await ConversionLimiter.shared.acquire(limit: maxConcurrentConversions)
            if Task.isCancelled {
                await ConversionLimiter.shared.release()
                break
            }
            do {
                try await run(preset: preset, inputURL: inputURL, outputURL: outputURL) { fileProgress in
                    let isIndeterminate = fileProgress < 0
                    update(.init(
                        state: .running,
                        progress: isIndeterminate
                            ? Double(completedBeforeFile) / Double(max(total, 1))
                            : (Double(completedBeforeFile) + fileProgress) / Double(max(total, 1)),
                        subtitle: ImagePresetConversionRunner.progressSubtitle(
                            total: total,
                            saved: savedBeforeFile,
                            failed: failedBeforeFile,
                            outputFilename: outputURL.lastPathComponent
                        ),
                        isIndeterminate: isIndeterminate
                    ))
                }
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
                subtitle: ImagePresetConversionRunner.progressSubtitle(
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
            subtitle: ImagePresetConversionRunner.progressSubtitle(total: total, saved: saved, failed: failed)
        ))
    }

    private static func runParallelBatch(
        preset: VideoPreset,
        inputURLs: [URL],
        maxConcurrentConversions: Int,
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        let total = inputURLs.count
        var saved = 0
        var failed = 0
        update(.init(state: .running, progress: 0, subtitle: "0 of \(total) saved", isIndeterminate: true))
        let jobs = ImagePresetConversionRunner.reservedOutputURLs(
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
                        try await run(
                            preset: preset,
                            inputURL: inputURL,
                            outputURL: outputURL,
                            progress: { _ in }
                        )
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
                    subtitle: ImagePresetConversionRunner.progressSubtitle(
                        total: total,
                        saved: saved,
                        failed: failed
                    )
                ))
            }
        }

        update(.init(
            state: failed == 0 ? .finished : .failed,
            progress: 1,
            subtitle: ImagePresetConversionRunner.progressSubtitle(
                total: total,
                saved: saved,
                failed: failed
            )
        ))
    }

    static func run(
        preset: VideoPreset,
        inputURL: URL,
        outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let installation = FFmpegInstall.installation else {
            throw ImagePresetConversionError.ffmpegNotInstalled
        }

        let mediaDuration: Double? = installation.ffprobeURL.flatMap {
            Self.duration(of: inputURL, ffprobeURL: $0)
        }
        guard let mediaDuration, mediaDuration > 0 else {
            progress(-1)
            try await runWithoutMeasuredProgress(
                preset: preset,
                inputURL: inputURL,
                outputURL: outputURL,
                installation: installation
            )
            return
        }

        progress(-1)

        let process = Process()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            let output = Pipe()
            let parser = FFmpegProgressParser(duration: mediaDuration, progress: progress)
            process.executableURL = installation.ffmpegURL
            process.arguments = ["-progress", "pipe:1", "-nostats"] + VideoFFmpegCommandBuilder.arguments(
                outputFormat: preset.outputFormat,
                options: preset.options,
                inputURL: inputURL,
                outputURL: outputURL
            )
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            output.fileHandleForReading.readabilityHandler = { handle in
                parser.consume(handle.availableData)
            }
            process.terminationHandler = { process in
                output.fileHandleForReading.readabilityHandler = nil
                parser.consume(output.fileHandleForReading.readDataToEndOfFile())
                if process.terminationStatus == 0 {
                    progress(1)
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ImagePresetConversionError.commandFailed(process.terminationStatus))
                }
            }

            do {
                try process.run()
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private static func runWithoutMeasuredProgress(
        preset: VideoPreset,
        inputURL: URL,
        outputURL: URL,
        installation: FFmpegInstallation
    ) async throws {
        let process = Process()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            process.executableURL = installation.ffmpegURL
            process.arguments = VideoFFmpegCommandBuilder.arguments(
                outputFormat: preset.outputFormat,
                options: preset.options,
                inputURL: inputURL,
                outputURL: outputURL
            )
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ImagePresetConversionError.commandFailed(process.terminationStatus))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    static func duration(of inputURL: URL, ffprobeURL: URL) -> Double? {
        let process = Process()
        let output = Pipe()
        process.executableURL = ffprobeURL
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            inputURL.path,
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let value = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(value)
    }
}

final class FFmpegProgressParser: @unchecked Sendable {
    private let duration: Double
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var buffer = ""

    init(duration: Double, progress: @escaping @Sendable (Double) -> Void) {
        self.duration = duration
        self.progress = progress
    }

    func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer += String(decoding: data, as: UTF8.self)
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        buffer = String(lines.last ?? "")
        let completedLines = lines.dropLast()
        lock.unlock()

        for line in completedLines {
            guard let value = Self.seconds(from: String(line)) else { continue }
            progress(min(max(value / duration, 0), 0.99))
        }
    }

    static func seconds(from line: String) -> Double? {
        guard line.hasPrefix("out_time_us="),
              let microseconds = Double(line.dropFirst("out_time_us=".count)) else { return nil }
        return microseconds / 1_000_000
    }
}
