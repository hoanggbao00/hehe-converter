import Foundation

enum VideoPresetConversionRunner {
    static func runBatch(
        preset: VideoPreset,
        inputURLs: [URL],
        mode: MultipleFileConversionMode = .sequential,
        maxConcurrentConversions: Int = 2,
        cancellation: ConversionCancellationController = ConversionCancellationController(),
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        if mode == .parallel, inputURLs.count > 1 {
            await runParallelBatch(
                preset: preset,
                inputURLs: inputURLs,
                maxConcurrentConversions: maxConcurrentConversions,
                cancellation: cancellation,
                update: update
            )
            return
        }

        let jobs = ImagePresetConversionRunner.conversionJobs(
            for: inputURLs,
            outputExtension: preset.outputFormat.fileExtension
        )
        let total = jobs.count
        var saved = 0
        var failed = 0
        var canceled = 0
        var items = jobs.map { ConversionProgressItem(id: $0.id, filename: $0.outputURL.lastPathComponent) }
        update(.init(
            state: .running,
            progress: 0,
            subtitle: ImagePresetConversionRunner.progressSubtitle(total: total, saved: 0, failed: 0),
            items: items
        ))

        for job in jobs {
            if Task.isCancelled { break }
            if cancellation.isCanceled(job.id) {
                canceled += 1
                items.update(job.id, status: .canceled, progress: 0, isIndeterminate: false)
                continue
            }
            items.update(job.id, status: .running, progress: 0, isIndeterminate: true)
            update(.init(
                state: .running,
                progress: Double(saved + failed + canceled) / Double(max(total, 1)),
                subtitle: ImagePresetConversionRunner.progressSubtitle(
                    total: total,
                    saved: saved,
                    failed: failed,
                    canceled: canceled,
                    outputFilename: job.outputURL.lastPathComponent
                ),
                isIndeterminate: true,
                items: items
            ))

            let completedBeforeFile = saved + failed
            let savedBeforeFile = saved
            let failedBeforeFile = failed
            let canceledBeforeFile = canceled
            let itemsBeforeFile = items
            await ConversionLimiter.shared.acquire(limit: maxConcurrentConversions)
            if Task.isCancelled || cancellation.isCanceled(job.id) {
                await ConversionLimiter.shared.release()
                canceled += 1
                items.update(job.id, status: .canceled, progress: 0, isIndeterminate: false)
                continue
            }
            let result = await runSequentialJob(
                preset: preset,
                job: job,
                cancellation: cancellation
            ) { fileProgress in
                    guard !cancellation.isCanceled(job.id) else { return }
                    let isIndeterminate = fileProgress < 0
                    var progressItems = itemsBeforeFile
                    progressItems.update(
                        job.id,
                        status: .running,
                        progress: isIndeterminate ? 0 : fileProgress,
                        isIndeterminate: isIndeterminate
                    )
                    update(.init(
                        state: .running,
                        progress: isIndeterminate
                            ? Double(completedBeforeFile + canceledBeforeFile) / Double(max(total, 1))
                            : (Double(completedBeforeFile + canceledBeforeFile) + fileProgress) / Double(max(total, 1)),
                        subtitle: ImagePresetConversionRunner.progressSubtitle(
                            total: total,
                            saved: savedBeforeFile,
                            failed: failedBeforeFile,
                            canceled: canceledBeforeFile,
                            outputFilename: job.outputURL.lastPathComponent
                        ),
                        isIndeterminate: isIndeterminate,
                        items: progressItems
                    ))
                }
            await ConversionLimiter.shared.release()
            switch result.status {
            case .saved:
                saved += 1
                items.update(job.id, status: .saved, progress: 1, isIndeterminate: false)
            case .failed:
                failed += 1
                items.update(job.id, status: .failed, progress: 1, isIndeterminate: false)
            case .canceled:
                canceled += 1
                items.update(job.id, status: .canceled, progress: 0, isIndeterminate: false)
                if Task.isCancelled { break }
            default:
                break
            }

            update(.init(
                state: .running,
                progress: Double(saved + failed + canceled) / Double(max(total, 1)),
                subtitle: ImagePresetConversionRunner.progressSubtitle(
                    total: total,
                    saved: saved,
                    failed: failed,
                    canceled: canceled,
                    outputFilename: job.outputURL.lastPathComponent
                ),
                items: items
            ))
        }

        update(.init(
            state: failed == 0 ? .finished : .failed,
            progress: 1,
            subtitle: ImagePresetConversionRunner.progressSubtitle(total: total, saved: saved, failed: failed, canceled: canceled),
            items: items
        ))
    }

    private static func runParallelBatch(
        preset: VideoPreset,
        inputURLs: [URL],
        maxConcurrentConversions: Int,
        cancellation: ConversionCancellationController,
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        let total = inputURLs.count
        var saved = 0
        var failed = 0
        var canceled = 0
        let jobs = ImagePresetConversionRunner.conversionJobs(
            for: inputURLs,
            outputExtension: preset.outputFormat.fileExtension
        )
        var items = jobs.map { ConversionProgressItem(id: $0.id, filename: $0.outputURL.lastPathComponent) }
        items.indices.forEach { items[$0].status = .running; items[$0].isIndeterminate = true }
        update(.init(state: .running, progress: 0, subtitle: "0 of \(total) saved", isIndeterminate: true, items: items))

        await withTaskGroup(of: ConversionJobResult.self) { group in
            for job in jobs {
                group.addTask {
                    if Task.isCancelled || cancellation.isCanceled(job.id) {
                        return .init(id: job.id, status: .canceled)
                    }
                    await ConversionLimiter.shared.acquire(limit: maxConcurrentConversions)
                    if Task.isCancelled || cancellation.isCanceled(job.id) {
                        await ConversionLimiter.shared.release()
                        return .init(id: job.id, status: .canceled)
                    }
                    do {
                        try await run(
                            preset: preset,
                            inputURL: job.inputURL,
                            outputURL: job.outputURL,
                            jobID: job.id,
                            cancellation: cancellation,
                            progress: { _ in }
                        )
                        await ConversionLimiter.shared.release()
                        return .init(id: job.id, status: .saved)
                    } catch {
                        await ConversionLimiter.shared.release()
                        if Task.isCancelled || cancellation.isCanceled(job.id) {
                            try? FileManager.default.removeItem(at: job.outputURL)
                            return .init(id: job.id, status: .canceled)
                        }
                        return .init(id: job.id, status: .failed)
                    }
                }
            }

            for await result in group {
                switch result.status {
                case .saved: saved += 1
                case .failed: failed += 1
                case .canceled: canceled += 1
                default: break
                }
                items.update(result.id, status: result.status, progress: result.status == .canceled ? 0 : 1, isIndeterminate: false)
                update(.init(
                    state: .running,
                    progress: Double(saved + failed + canceled) / Double(total),
                    subtitle: ImagePresetConversionRunner.progressSubtitle(
                        total: total,
                        saved: saved,
                        failed: failed,
                        canceled: canceled
                    ),
                    items: items
                ))
            }
        }

        update(.init(
            state: failed == 0 ? .finished : .failed,
            progress: 1,
            subtitle: ImagePresetConversionRunner.progressSubtitle(
                total: total,
                saved: saved,
                failed: failed,
                canceled: canceled
            ),
            items: items
        ))
    }

    private static func runSequentialJob(
        preset: VideoPreset,
        job: ConversionJob,
        cancellation: ConversionCancellationController,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> ConversionJobResult {
        let resultBox = ConversionJobResultBox()
        let conversionTask = Task {
            do {
                try await run(
                    preset: preset,
                    inputURL: job.inputURL,
                    outputURL: job.outputURL,
                    jobID: job.id,
                    cancellation: cancellation,
                    progress: progress
                )
                resultBox.set(.init(id: job.id, status: .saved))
            } catch {
                if Task.isCancelled || cancellation.isCanceled(job.id) {
                    try? FileManager.default.removeItem(at: job.outputURL)
                    resultBox.set(.init(id: job.id, status: .canceled))
                    return
                }
                resultBox.set(.init(id: job.id, status: .failed))
            }
        }

        while true {
            if Task.isCancelled || cancellation.isCanceled(job.id) {
                cancellation.cancel(job.id)
                conversionTask.cancel()
                return .init(id: job.id, status: .canceled)
            }
            if let result = resultBox.result {
                return result
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    static func run(
        preset: VideoPreset,
        inputURL: URL,
        outputURL: URL,
        jobID: UUID? = nil,
        cancellation: ConversionCancellationController? = nil,
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
                installation: installation,
                jobID: jobID,
                cancellation: cancellation
            )
            return
        }

        progress(-1)

        defer {
            if let jobID { cancellation?.unregister(jobID) }
        }
        for backend in VideoFFmpegCommandBuilder.backends(for: preset.outputFormat) {
            do {
                try await runMeasuredProcess(
                    preset: preset,
                    inputURL: inputURL,
                    outputURL: outputURL,
                    installation: installation,
                    mediaDuration: mediaDuration,
                    backend: backend,
                    jobID: jobID,
                    cancellation: cancellation,
                    progress: progress
                )
                return
            } catch {
                if Task.isCancelled || (jobID.map({ cancellation?.isCanceled($0) == true }) ?? false) {
                    throw error
                }
                try? FileManager.default.removeItem(at: outputURL)
                guard backend == .hardware else { throw error }
                progress(-1)
            }
        }
    }

    private static func runMeasuredProcess(
        preset: VideoPreset,
        inputURL: URL,
        outputURL: URL,
        installation: FFmpegInstallation,
        mediaDuration: Double,
        backend: VideoFFmpegCommandBuilder.Backend,
        jobID: UUID?,
        cancellation: ConversionCancellationController?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let process = Process()
        if let jobID, let cancellation {
            cancellation.register(process, for: jobID)
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            let output = Pipe()
            let parser = FFmpegProgressParser(duration: mediaDuration, progress: progress)
            process.executableURL = installation.ffmpegURL
            process.arguments = ["-progress", "pipe:1", "-nostats"] + VideoFFmpegCommandBuilder.arguments(
                outputFormat: preset.outputFormat,
                options: preset.options,
                inputURL: inputURL,
                outputURL: outputURL,
                backend: backend
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
        installation: FFmpegInstallation,
        jobID: UUID?,
        cancellation: ConversionCancellationController?
    ) async throws {
        defer {
            if let jobID { cancellation?.unregister(jobID) }
        }
        for backend in VideoFFmpegCommandBuilder.backends(for: preset.outputFormat) {
            do {
                try await runUnmeasuredProcess(
                    preset: preset,
                    inputURL: inputURL,
                    outputURL: outputURL,
                    installation: installation,
                    backend: backend,
                    jobID: jobID,
                    cancellation: cancellation
                )
                return
            } catch {
                if Task.isCancelled || (jobID.map({ cancellation?.isCanceled($0) == true }) ?? false) {
                    throw error
                }
                try? FileManager.default.removeItem(at: outputURL)
                guard backend == .hardware else { throw error }
            }
        }
    }

    private static func runUnmeasuredProcess(
        preset: VideoPreset,
        inputURL: URL,
        outputURL: URL,
        installation: FFmpegInstallation,
        backend: VideoFFmpegCommandBuilder.Backend,
        jobID: UUID?,
        cancellation: ConversionCancellationController?
    ) async throws {
        let process = Process()
        if let jobID, let cancellation {
            cancellation.register(process, for: jobID)
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            process.executableURL = installation.ffmpegURL
            process.arguments = VideoFFmpegCommandBuilder.arguments(
                outputFormat: preset.outputFormat,
                options: preset.options,
                inputURL: inputURL,
                outputURL: outputURL,
                backend: backend
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
