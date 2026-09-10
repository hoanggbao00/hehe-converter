import CryptoKit
import Foundation

enum FFmpegInstall {
    static let binDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(AppConstants.managedBinRelativePath, isDirectory: true)

    static var ffmpegURL: URL { binDirectory.appendingPathComponent("ffmpeg") }
    static var ffprobeURL: URL { binDirectory.appendingPathComponent("ffprobe") }
    private static var metadataURL: URL { binDirectory.appendingPathComponent(".mediadrop-ffmpeg.json") }

    static var isInstalled: Bool {
        installation != nil
    }

    static var installation: FFmpegInstallation? {
        managedInstallation() ?? userInstallation()
    }

    static var needsVerification: Bool {
        guard FileManager.default.isExecutableFile(atPath: ffmpegURL.path) else { return false }
        return managedInstallation()?.isVerified != true
    }

    private static func managedInstallation() -> FFmpegInstallation? {
        guard FileManager.default.isExecutableFile(atPath: ffmpegURL.path) else { return nil }

        let hasFFprobe = FileManager.default.isExecutableFile(atPath: ffprobeURL.path)
        if let data = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(FFmpegInstallMetadata.self, from: data),
           metadata.sourceURL.flatMap(URL.init(string:)) != nil || metadata.source == .user,
           metadata.ffmpegSHA256 == (try? sha256(of: ffmpegURL)) {
            return FFmpegInstallation(
                source: metadata.source == .github ? .github : .user,
                sourceURL: metadata.sourceURL.flatMap(URL.init(string:)),
                version: metadata.version,
                ffmpegURL: ffmpegURL,
                hasFFprobe: hasFFprobe,
                isVerified: true
            )
        }

        return FFmpegInstallation(
            source: .user,
            sourceURL: nil,
            version: executableVersion(at: ffmpegURL) ?? "Unknown",
            ffmpegURL: ffmpegURL,
            hasFFprobe: hasFFprobe,
            isVerified: false
        )
    }

    private static func userInstallation() -> FFmpegInstallation? {
        guard let userFFmpegURL = userExecutable(named: "ffmpeg") else { return nil }
        return FFmpegInstallation(
            source: .user,
            sourceURL: nil,
            version: executableVersion(at: userFFmpegURL) ?? "Unknown",
            ffmpegURL: userFFmpegURL,
            hasFFprobe: userExecutable(named: "ffprobe", near: userFFmpegURL) != nil,
            isVerified: true
        )
    }

    static func deleteInstalledFiles() throws {
        let fileManager = FileManager.default
        for url in [ffmpegURL, ffprobeURL, metadataURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        if fileManager.fileExists(atPath: binDirectory.path),
           try fileManager.contentsOfDirectory(atPath: binDirectory.path).isEmpty {
            try fileManager.removeItem(at: binDirectory)
        }
    }

    static func writeManagedInstallMetadata(for release: FFmpegRelease) throws {
        let metadata = FFmpegInstallMetadata(
            source: .github,
            sourceURL: release.asset.downloadURL.absoluteString,
            version: release.version,
            ffmpegSHA256: try sha256(of: ffmpegURL)
        )
        try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
    }

    @discardableResult
    static func verifyInstalledFiles() throws -> FFmpegInstallation? {
        if FileManager.default.isExecutableFile(atPath: ffmpegURL.path) {
            return try verifyManagedFiles()
        }

        guard let userFFmpegURL = userExecutable(named: "ffmpeg") else { return nil }
        guard let version = executableVersion(at: userFFmpegURL) else {
            throw FFmpegInstallError.invalidExecutable("ffmpeg")
        }
        return FFmpegInstallation(
            source: .user,
            sourceURL: nil,
            version: version,
            ffmpegURL: userFFmpegURL,
            hasFFprobe: userExecutable(named: "ffprobe", near: userFFmpegURL) != nil,
            isVerified: true
        )
    }

    private static func verifyManagedFiles() throws -> FFmpegInstallation? {
        let fingerprint = try sha256(of: ffmpegURL)
        let hasFFprobe = FileManager.default.isExecutableFile(atPath: ffprobeURL.path)
        guard let version = executableVersion(at: ffmpegURL) else {
            throw FFmpegInstallError.invalidExecutable("ffmpeg")
        }
        let currentMetadata = readMetadata()

        let metadata: FFmpegInstallMetadata
        if let currentMetadata, currentMetadata.ffmpegSHA256 == fingerprint {
            metadata = FFmpegInstallMetadata(
                source: currentMetadata.source,
                sourceURL: currentMetadata.sourceURL,
                version: currentMetadata.version,
                ffmpegSHA256: fingerprint
            )
        } else {
            metadata = FFmpegInstallMetadata(
                source: .user,
                sourceURL: nil,
                version: version,
                ffmpegSHA256: fingerprint
            )
        }

        try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
        return FFmpegInstallation(
            source: metadata.source == .github ? .github : .user,
            sourceURL: metadata.sourceURL.flatMap(URL.init(string:)),
            version: metadata.version,
            ffmpegURL: ffmpegURL,
            hasFFprobe: hasFFprobe,
            isVerified: true
        )
    }

    private static func readMetadata() -> FFmpegInstallMetadata? {
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        if let metadata = try? JSONDecoder().decode(FFmpegInstallMetadata.self, from: data) {
            return metadata
        }

        guard let legacy = try? JSONDecoder().decode(LegacyFFmpegInstallMetadata.self, from: data),
              legacy.repository == FFmpegDistribution.repository else {
            return nil
        }

        return FFmpegInstallMetadata(
            source: .github,
            sourceURL: FFmpegDistribution.repositoryURL.absoluteString,
            version: legacy.version,
            ffmpegSHA256: legacy.ffmpegSHA256
        )
    }

    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func executableVersion(at executableURL: URL) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["-version"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let line = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n", maxSplits: 1)
            .first?
            .split(separator: " ")
        guard let line, line.count >= 3, line[0] == "ffmpeg", line[1] == "version" else { return nil }
        return String(line[2])
    }

    private static func userExecutable(named name: String, near nearFFmpegURL: URL? = nil) -> URL? {
        var candidates: [URL] = []
        if let nearFFmpegURL {
            candidates.append(nearFFmpegURL.deletingLastPathComponent().appendingPathComponent(name))
        }
        candidates += [
            URL(fileURLWithPath: "/opt/homebrew/bin/").appendingPathComponent(name),
            URL(fileURLWithPath: "/usr/local/bin/").appendingPathComponent(name),
            URL(fileURLWithPath: "/opt/local/bin/").appendingPathComponent(name)
        ]
        if let pathURL = which(name) {
            candidates.append(pathURL)
        }

        return candidates.first { url in
            url != (name == "ffmpeg" ? Self.ffmpegURL : Self.ffprobeURL)
                && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    private static func which(_ name: String) -> URL? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let path = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}

struct FFmpegInstallation: Equatable {
    enum Source: Equatable {
        case github
        case user
    }

    let source: Source
    let sourceURL: URL?
    let version: String
    let ffmpegURL: URL
    let hasFFprobe: Bool
    let isVerified: Bool
}

private struct FFmpegInstallMetadata: Codable {
    enum Source: String, Codable {
        case github
        case user
    }

    let source: Source
    let sourceURL: String?
    let version: String
    let ffmpegSHA256: String
}

private struct LegacyFFmpegInstallMetadata: Codable {
    let repository: String
    let version: String
    let ffmpegSHA256: String
}

enum FFmpegInstallStep: String, CaseIterable, Sendable {
    case fetch = "Fetching release"
    case download = "Downloading archive"
    case verify = "Verifying checksum"
    case unzip = "Unzipping archive"
    case copy = "Copying binaries"
}

enum FFmpegInstallError: LocalizedError {
    case checksumMismatch(expected: String, actual: String)
    case invalidExecutable(String)
    case missingExecutable(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case let .checksumMismatch(expected, actual):
            "Checksum mismatch. Expected \(expected), got \(actual)."
        case let .invalidExecutable(name):
            "\(name) could not run or report its version."
        case let .missingExecutable(name):
            "Missing \(name) in downloaded archive."
        case let .processFailed(command):
            "Command failed: \(command)."
        }
    }
}

enum FFmpegInstaller {
    static func install(
        release: FFmpegRelease,
        progress: @escaping @Sendable (Double) -> Void,
        step: @escaping @Sendable (FFmpegInstallStep) -> Void
    ) async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("MediaDrop-FFmpeg-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = tempRoot.appendingPathComponent(release.asset.name)
        let extractURL = tempRoot.appendingPathComponent("extract", isDirectory: true)

        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        step(.fetch)
        progress(0.01)
        try Task.checkCancellation()

        step(.download)
        try await download(release.asset, to: archiveURL) { downloadProgress in
            progress(0.02 + downloadProgress * 0.73)
        }
        try Task.checkCancellation()

        step(.verify)
        progress(0.78)
        try verifyChecksum(of: archiveURL, expected: release.asset.sha256)
        try Task.checkCancellation()

        step(.unzip)
        progress(0.84)
        try extractArchive(archiveURL, to: extractURL)
        try Task.checkCancellation()

        step(.copy)
        progress(0.94)
        try installExecutables(from: extractURL, release: release)
        progress(1)
    }

    private static func download(
        _ asset: FFmpegAsset,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let downloader = DownloadDelegate(destination: destination, expectedSize: asset.size, progress: progress)
        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                downloader.continuation = continuation
                session.downloadTask(with: asset.downloadURL).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    private static func verifyChecksum(of fileURL: URL, expected: String) throws {
        let hash = try FFmpegInstall.sha256(of: fileURL)

        guard hash == expected else {
            throw FFmpegInstallError.checksumMismatch(
                expected: expected,
                actual: hash
            )
        }
    }

    private static func extractArchive(_ archiveURL: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, destination.path])
    }

    private static func installExecutables(from directory: URL, release: FFmpegRelease) throws {
        let ffmpeg = try findExecutable(named: "ffmpeg", in: directory)
        let ffprobe = try findExecutable(named: "ffprobe", in: directory)

        try FileManager.default.createDirectory(at: FFmpegInstall.binDirectory, withIntermediateDirectories: true)
        try replace(ffmpeg, with: FFmpegInstall.ffmpegURL)
        try replace(ffprobe, with: FFmpegInstall.ffprobeURL)
        try run("/bin/chmod", arguments: ["755", FFmpegInstall.ffmpegURL.path, FFmpegInstall.ffprobeURL.path])
        try FFmpegInstall.writeManagedInstallMetadata(for: release)
    }

    private static func findExecutable(named name: String, in directory: URL) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw FFmpegInstallError.missingExecutable(name)
        }

        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == name {
            return fileURL
        }

        throw FFmpegInstallError.missingExecutable(name)
    }

    private static func replace(_ source: URL, with destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func run(_ launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw FFmpegInstallError.processFailed(([launchPath] + arguments).joined(separator: " "))
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    fileprivate var continuation: CheckedContinuation<Void, Error>?
    private let destination: URL
    private let expectedSize: Int64
    private let progress: @Sendable (Double) -> Void

    init(destination: URL, expectedSize: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expectedBytes = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : expectedSize
        progress(min(Double(totalBytesWritten) / Double(expectedBytes), 0.99))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
