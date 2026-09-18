import AppKit
import CryptoKit
import Foundation

struct AppVersion: Comparable, Equatable {
    let components: [Int]

    init?(_ value: String) {
        let normalized = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        components = parts.map { Int($0)! }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

struct AppRelease: Equatable {
    let version: String
    let pageURL: URL
    let downloadURL: URL
    let size: Int64
    let sha256: String
}

struct AppReleaseNotes: Equatable {
    let version: String
    let pageURL: URL
    let body: String
}

enum AppUpdateError: LocalizedError {
    case invalidResponse(Int?)
    case invalidRelease
    case checksumMismatch
    case mountFailed(String)
    case appNotFound
    case invalidApp
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let status):
            status.map { "Could not check for updates (HTTP \($0))." }
                ?? "Could not check for updates."
        case .invalidRelease: "Latest release has no verified DMG."
        case .checksumMismatch: "Downloaded update failed checksum verification."
        case .mountFailed(let message): "Could not mount update: \(message)"
        case .appNotFound: "Downloaded DMG contains no HeheConverter app."
        case .invalidApp: "Downloaded app identity or version is invalid."
        case .installFailed(let message): "Could not prepare update: \(message)"
        }
    }
}

struct AppUpdateService {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/hoanggbao00/hehe-converter/releases/latest"
    )!

    static func releaseURL(version: String) -> URL {
        URL(string: "https://api.github.com/repos/hoanggbao00/hehe-converter/releases/tags/v\(version)")!
    }

    func latestRelease(session: URLSession = .shared) async throws -> AppRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HeheConverter", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppUpdateError.invalidResponse((response as? HTTPURLResponse)?.statusCode)
        }
        return try Self.decodeRelease(from: data)
    }

    func releaseNotes(for version: String, session: URLSession = .shared) async throws -> AppReleaseNotes {
        var request = URLRequest(url: Self.releaseURL(version: version))
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HeheConverter", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppUpdateError.invalidResponse((response as? HTTPURLResponse)?.statusCode)
        }
        return try Self.decodeReleaseNotes(from: data)
    }

    static func decodeRelease(from data: Data) throws -> AppRelease {
        let release = try JSONDecoder().decode(GitHubAppRelease.self, from: data)
        guard !release.draft, !release.prerelease,
              AppVersion(release.tagName) != nil,
              let pageURL = URL(string: release.htmlURL),
              let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
              let downloadURL = URL(string: asset.downloadURL),
              let digest = asset.digest,
              digest.lowercased().hasPrefix("sha256:")
        else { throw AppUpdateError.invalidRelease }

        return AppRelease(
            version: String(release.tagName.drop(while: { $0 == "v" })),
            pageURL: pageURL,
            downloadURL: downloadURL,
            size: asset.size,
            sha256: String(digest.dropFirst("sha256:".count)).lowercased()
        )
    }

    static func decodeReleaseNotes(from data: Data) throws -> AppReleaseNotes {
        let release = try JSONDecoder().decode(GitHubAppRelease.self, from: data)
        guard !release.draft, !release.prerelease,
              AppVersion(release.tagName) != nil,
              let pageURL = URL(string: release.htmlURL)
        else { throw AppUpdateError.invalidRelease }

        return AppReleaseNotes(
            version: String(release.tagName.drop(while: { $0 == "v" })),
            pageURL: pageURL,
            body: release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    func downloadAndInstall(
        _ release: AppRelease,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let fileManager = FileManager.default
        let workURL = fileManager.temporaryDirectory
            .appendingPathComponent("HeheConverter-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workURL, withIntermediateDirectories: true)
        var mountedURL: URL?

        do {
            let dmgURL = workURL.appendingPathComponent("update.dmg")
            try await Self.download(release, to: dmgURL, progress: progress)
            try Task.checkCancellation()
            guard try Self.sha256(of: dmgURL) == release.sha256 else {
                throw AppUpdateError.checksumMismatch
            }
            try Task.checkCancellation()

            let mountURL = try Self.mount(dmgURL)
            mountedURL = mountURL
            let sourceAppURL = try Self.findApp(in: mountURL)
            try Self.validateApp(sourceAppURL, expectedVersion: release.version)
            try await Self.stageAndRelaunch(
                sourceAppURL: sourceAppURL,
                mountURL: mountURL,
                workURL: workURL
            )
        } catch {
            if let mountedURL {
                _ = try? Self.run("/usr/bin/hdiutil", ["detach", mountedURL.path])
            }
            try? fileManager.removeItem(at: workURL)
            throw error
        }
    }

    private static func download(
        _ release: AppRelease,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = AppUpdateDownloadDelegate(
            destination: destination,
            expectedSize: release.size,
            progress: progress
        )
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                session.downloadTask(with: release.downloadURL).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    private static func sha256(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private static func mount(_ dmgURL: URL) throws -> URL {
        let result = try run("/usr/bin/hdiutil", ["attach", dmgURL.path, "-nobrowse", "-plist"])
        guard result.status == 0,
              let plist = try PropertyListSerialization.propertyList(
                from: result.output,
                format: nil
              ) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let path = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw AppUpdateError.mountFailed(String(data: result.error, encoding: .utf8) ?? "Unknown error")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func findApp(in mountURL: URL) throws -> URL {
        let direct = mountURL.appendingPathComponent("HeheConverter.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        guard let app = try FileManager.default.contentsOfDirectory(
            at: mountURL,
            includingPropertiesForKeys: nil
        ).first(where: { $0.pathExtension == "app" }) else {
            throw AppUpdateError.appNotFound
        }
        return app
    }

    private static func validateApp(_ appURL: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == AppConstants.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion
        else { throw AppUpdateError.invalidApp }
    }

    @MainActor
    private static func stageAndRelaunch(
        sourceAppURL: URL,
        mountURL: URL,
        workURL: URL
    ) throws {
        let targetURL = Bundle.main.bundleURL
        let stagedURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent(".HeheConverter-update.app", isDirectory: true)
        let backupURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent(".HeheConverter-backup.app", isDirectory: true)

        try? FileManager.default.removeItem(at: stagedURL)
        let copy = try run("/usr/bin/ditto", [sourceAppURL.path, stagedURL.path])
        guard copy.status == 0 else {
            throw AppUpdateError.installFailed(String(data: copy.error, encoding: .utf8) ?? "Unknown error")
        }
        try validateApp(stagedURL, expectedVersion: Bundle(url: sourceAppURL)?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")

        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.1; done
        rm -rf "$4"
        if mv "$2" "$4" && mv "$3" "$2"; then
          open "$2"
          rm -rf "$4"
        else
          test -e "$2" || mv "$4" "$2"
          open "$2"
        fi
        hdiutil detach "$5" >/dev/null 2>&1 || true
        rm -rf "$6"
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c", script, "update-helper", String(ProcessInfo.processInfo.processIdentifier),
            targetURL.path, stagedURL.path, backupURL.path, mountURL.path, workURL.path
        ]
        do {
            try helper.run()
        } catch {
            try? FileManager.default.removeItem(at: stagedURL)
            throw AppUpdateError.installFailed(error.localizedDescription)
        }
        NSApp.terminate(nil)
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> (
        status: Int32,
        output: Data,
        error: Data
    ) {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            output.fileHandleForReading.readDataToEndOfFile(),
            error.fileHandleForReading.readDataToEndOfFile()
        )
    }
}

private struct GitHubAppRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let body: String?
    let assets: [GitHubAppAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease, body, assets
    }
}

private struct GitHubAppAsset: Decodable {
    let name: String
    let digest: String?
    let downloadURL: String
    let size: Int64

    enum CodingKeys: String, CodingKey {
        case name, digest, size
        case downloadURL = "browser_download_url"
    }
}

private final class AppUpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var continuation: CheckedContinuation<Void, Error>?
    private let destination: URL
    private let expectedSize: Int64
    private let progress: @Sendable (Double) -> Void

    init(
        destination: URL,
        expectedSize: Int64,
        progress: @escaping @Sendable (Double) -> Void
    ) {
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
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        guard total > 0 else { return }
        progress(min(Double(totalBytesWritten) / Double(total), 1))
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
