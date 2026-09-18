import Foundation

enum ArchiveAction: String, CaseIterable {
    case unzipHere = "Unzip"
    case unzipToFolder = "Unzip (New Folder)"

    var systemImage: String {
        switch self {
        case .unzipHere: "archivebox"
        case .unzipToFolder: "folder.badge.plus"
        }
    }
}

enum ArchiveUnzipRunner {
    static func runBatch(
        inputURLs: [URL],
        action: ArchiveAction,
        cancellation: ConversionCancellationController,
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        let jobs = extractionJobs(for: inputURLs, action: action)
        var items = jobs.map { ConversionProgressItem(id: $0.id, filename: $0.inputURL.lastPathComponent) }
        var saved = 0
        var failed = 0
        var canceled = 0

        update(.init(state: .running, progress: 0, subtitle: "Preparing", items: items))
        for job in jobs {
            if Task.isCancelled || cancellation.isCanceled(job.id) {
                canceled += 1
                items.update(job.id, status: .canceled, progress: 0, isIndeterminate: false)
                continue
            }

            items.update(job.id, status: .running, progress: 0, isIndeterminate: true)
            update(.init(
                state: .running,
                progress: Double(saved + failed + canceled) / Double(max(jobs.count, 1)),
                subtitle: "Extracting \(job.inputURL.lastPathComponent)",
                isIndeterminate: true,
                items: items
            ))

            do {
                try await run(job: job, action: action, cancellation: cancellation)
                saved += 1
                items.update(job.id, status: .saved, progress: 1, isIndeterminate: false)
            } catch is CancellationError {
                canceled += 1
                items.update(job.id, status: .canceled, progress: 0, isIndeterminate: false)
            } catch {
                failed += 1
                items.update(job.id, status: .failed, progress: 1, isIndeterminate: false)
            }
        }

        let subtitle = jobs.count == 1
            ? (canceled > 0 ? "Canceled" : failed > 0 ? "Failed" : "Extracted")
            : "\(saved) of \(jobs.count) extracted" + (failed > 0 ? ", \(failed) failed" : "")
        update(.init(
            state: failed == 0 ? .finished : .failed,
            progress: 1,
            subtitle: subtitle,
            items: items
        ))
    }

    static func extractionJobs(
        for inputURLs: [URL],
        action: ArchiveAction,
        fileManager: FileManager = .default
    ) -> [ConversionJob] {
        var reservedPaths = Set<String>()
        return inputURLs.map { inputURL in
            let outputURL = action == .unzipToFolder ? availableOutputURL(
                for: inputURL,
                fileManager: fileManager,
                reservedPaths: reservedPaths
            ) : inputURL.deletingLastPathComponent()
            reservedPaths.insert(outputURL.path)
            return ConversionJob(id: UUID(), inputURL: inputURL, outputURL: outputURL)
        }
    }

    static func availableOutputURL(
        for inputURL: URL,
        fileManager: FileManager = .default,
        reservedPaths: Set<String> = []
    ) -> URL {
        let parent = inputURL.deletingLastPathComponent()
        let basename = inputURL.deletingPathExtension().lastPathComponent
        var index = 0
        while true {
            let name = index == 0 ? basename : "\(basename)-\(index)"
            let candidate = parent.appendingPathComponent(name, isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path), !reservedPaths.contains(candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private static func run(job: ConversionJob, action: ArchiveAction, cancellation: ConversionCancellationController) async throws {
        let fileManager = FileManager.default
        let temporaryParent = action == .unzipToFolder ? job.outputURL.deletingLastPathComponent() : job.outputURL
        let temporaryURL = temporaryParent
            .appendingPathComponent(".hehe-unzip-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", job.inputURL.path, temporaryURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        cancellation.register(process, for: job.id)
        defer { cancellation.unregister(job.id) }

        try await withTaskCancellationHandler {
            try process.run()
            process.waitUntilExit()
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        guard !Task.isCancelled, !cancellation.isCanceled(job.id) else {
            throw CancellationError()
        }
        guard process.terminationStatus == 0 else {
            throw ArchiveUnzipError.commandFailed(process.terminationStatus)
        }
        switch action {
        case .unzipHere:
            try moveContents(from: temporaryURL, to: job.outputURL, fileManager: fileManager)
        case .unzipToFolder:
            try fileManager.moveItem(at: temporaryURL, to: job.outputURL)
        }
    }

    private static func moveContents(from source: URL, to destination: URL, fileManager: FileManager) throws {
        let children = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: []
        )
        for child in children {
            let target = availableChildURL(for: child.lastPathComponent, in: destination, fileManager: fileManager)
            try fileManager.moveItem(at: child, to: target)
        }
    }

    private static func availableChildURL(for filename: String, in directory: URL, fileManager: FileManager) -> URL {
        let original = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: original.path) else { return original }

        let url = URL(fileURLWithPath: filename)
        let basename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var index = 1
        while true {
            let name = ext.isEmpty ? "\(basename)-\(index)" : "\(basename)-\(index).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}

enum ArchiveUnzipError: Error {
    case commandFailed(Int32)
}
