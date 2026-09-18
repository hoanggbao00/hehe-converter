import Foundation

enum ImagePresetConversionRunner {
    static func runBatch(
        preset: ImagePreset,
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

        let jobs = conversionJobs(for: inputURLs, outputExtension: preset.outputFormat.fileExtension)
        let total = jobs.count
        var saved = 0
        var failed = 0
        var canceled = 0
        var items = jobs.map { ConversionProgressItem(id: $0.id, filename: $0.outputURL.lastPathComponent) }
        sendProgress(state: .running, total: total, saved: saved, failed: failed, canceled: canceled, items: items, update: update)

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
                progress: Double(saved + failed) / Double(max(total, 1)),
                subtitle: progressSubtitle(
                    total: total,
                    saved: saved,
                    failed: failed,
                    canceled: canceled,
                    outputFilename: job.outputURL.lastPathComponent
                ),
                isIndeterminate: true,
                items: items
            ))

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
            )
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
                progress: Double(saved + failed) / Double(max(total, 1)),
                subtitle: progressSubtitle(
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
            subtitle: progressSubtitle(total: total, saved: saved, failed: failed, canceled: canceled),
            items: items
        ))
    }

    private static func runParallelBatch(
        preset: ImagePreset,
        inputURLs: [URL],
        maxConcurrentConversions: Int,
        cancellation: ConversionCancellationController,
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        let total = inputURLs.count
        var saved = 0
        var failed = 0
        var canceled = 0
        let jobs = conversionJobs(for: inputURLs, outputExtension: preset.outputFormat.fileExtension)
        var items = jobs.map { ConversionProgressItem(id: $0.id, filename: $0.outputURL.lastPathComponent) }
        update(.init(state: .running, progress: 0, subtitle: progressSubtitle(total: total, saved: saved, failed: failed, canceled: canceled), isIndeterminate: true, items: items))

        await withTaskGroup(of: ConversionJobResult.self) { group in
            for job in jobs {
                items.update(job.id, status: .running, progress: 0, isIndeterminate: true)
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
                            cancellation: cancellation
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

            update(.init(state: .running, progress: 0, subtitle: progressSubtitle(total: total, saved: saved, failed: failed, canceled: canceled), isIndeterminate: true, items: items))

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
                    subtitle: progressSubtitle(total: total, saved: saved, failed: failed, canceled: canceled),
                    items: items
                ))
            }
        }

        update(.init(
            state: failed == 0 ? .finished : .failed,
            progress: 1,
            subtitle: progressSubtitle(total: total, saved: saved, failed: failed, canceled: canceled),
            items: items
        ))
    }

    private static func runSequentialJob(
        preset: ImagePreset,
        job: ConversionJob,
        cancellation: ConversionCancellationController
    ) async -> ConversionJobResult {
        let resultBox = ConversionJobResultBox()
        let conversionTask = Task {
            do {
                try await run(
                    preset: preset,
                    inputURL: job.inputURL,
                    outputURL: job.outputURL,
                    jobID: job.id,
                    cancellation: cancellation
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

    static func conversionJobs(
        for inputURLs: [URL],
        outputExtension: String,
        preservesInputExtension: Bool = false,
        outputNameSuffix: String? = nil,
        fileManager: FileManager = .default
    ) -> [ConversionJob] {
        reservedOutputURLs(
            for: inputURLs,
            outputExtension: outputExtension,
            preservesInputExtension: preservesInputExtension,
            outputNameSuffix: outputNameSuffix,
            fileManager: fileManager
        )
            .map { ConversionJob(id: UUID(), inputURL: $0.inputURL, outputURL: $0.outputURL) }
    }

    static func reservedOutputURLs(
        for inputURLs: [URL],
        outputExtension: String,
        preservesInputExtension: Bool = false,
        outputNameSuffix: String? = nil,
        fileManager: FileManager = .default
    ) -> [(inputURL: URL, outputURL: URL)] {
        var reservedPaths = Set<String>()
        return inputURLs.map { inputURL in
            let outputURL = availableOutputURL(
                for: inputURL,
                outputExtension: preservesInputExtension ? inputURL.pathExtension : outputExtension,
                outputNameSuffix: outputNameSuffix,
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
        canceled: Int = 0,
        outputFilename: String? = nil
    ) -> String {
        if total == 1 {
            return outputFilename ?? (canceled > 0 ? "Canceled" : failed > 0 ? "Failed" : "Saved")
        }

        let savedText = "\(saved) of \(total) saved"
        var parts = [savedText]
        if failed > 0 { parts.append("\(failed) failed") }
        if canceled > 0 { parts.append("\(canceled) canceled") }
        return parts.joined(separator: ", ")
    }

    private static func sendProgress(
        state: ImagePresetConversionUpdate.State,
        total: Int,
        saved: Int,
        failed: Int,
        canceled: Int,
        items: [ConversionProgressItem],
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) {
        update(.init(
            state: state,
            progress: Double(saved + failed + canceled) / Double(max(total, 1)),
            subtitle: progressSubtitle(total: total, saved: saved, failed: failed, canceled: canceled),
            items: items
        ))
    }

    static func run(
        preset: ImagePreset,
        inputURL: URL,
        outputURL: URL,
        jobID: UUID? = nil,
        cancellation: ConversionCancellationController? = nil
    ) async throws {
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
        if let jobID, let cancellation {
            cancellation.register(process, for: jobID)
            if cancellation.isCanceled(jobID) { throw CancellationError() }
        }
        defer {
            if let jobID { cancellation?.unregister(jobID) }
        }

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
            .appendingPathComponent("HeheConverter-SVG-\(UUID().uuidString)", isDirectory: true)
        let outputURL = directory
            .appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("png")
        try await SVGImageRasterizer.rasterize(inputURL: inputURL, outputURL: outputURL)
        return outputURL
    }

    static func availableOutputURL(
        for inputURL: URL,
        outputExtension: String,
        outputNameSuffix: String? = nil,
        fileManager: FileManager = .default,
        reservedPaths: Set<String> = []
    ) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let basename = inputURL.deletingPathExtension().lastPathComponent
        let normalizedExtension = outputExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let outputBasename = outputNameSuffix.map { "\(basename)-\($0)" } ?? basename

        func candidate(_ suffix: Int?) -> URL {
            let name = suffix.map { "\(outputBasename)-\($0)" } ?? outputBasename
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
    var items: [ConversionProgressItem] = []
}

struct ConversionJob: Identifiable, Sendable {
    let id: UUID
    let inputURL: URL
    let outputURL: URL
}

struct ConversionJobResult: Sendable {
    let id: UUID
    let status: ConversionProgressItem.Status
}

final class ConversionJobResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: ConversionJobResult?

    var result: ConversionJobResult? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    func set(_ result: ConversionJobResult) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }
}

final class ConversionCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var canceledIDs = Set<UUID>()
    private var processes: [UUID: Process] = [:]

    func cancel(_ id: UUID) {
        lock.lock()
        canceledIDs.insert(id)
        let process = processes[id]
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func isCanceled(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return canceledIDs.contains(id)
    }

    func register(_ process: Process, for id: UUID) {
        lock.lock()
        processes[id] = process
        let shouldCancel = canceledIDs.contains(id)
        lock.unlock()

        if shouldCancel, process.isRunning {
            process.terminate()
        }
    }

    func unregister(_ id: UUID) {
        lock.lock()
        processes[id] = nil
        lock.unlock()
    }
}

struct ConversionProgressItem: Identifiable, Sendable, Equatable {
    enum Status: Sendable, Equatable {
        case pending
        case running
        case saved
        case failed
        case canceled
    }

    let id: UUID
    let filename: String
    var status: Status = .pending
    var progress = 0.0
    var isIndeterminate = false
}

extension Array where Element == ConversionProgressItem {
    mutating func update(
        _ id: UUID,
        status: ConversionProgressItem.Status,
        progress: Double,
        isIndeterminate: Bool
    ) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].status = status
        self[index].progress = progress
        self[index].isIndeterminate = isIndeterminate
    }
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
