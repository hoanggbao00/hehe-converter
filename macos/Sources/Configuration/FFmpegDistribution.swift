import Foundation

enum FFmpegDistribution {
    static let repository = "Tyrrrz/FFmpegBin"
    static let repositoryURL = URL(string: "https://github.com/Tyrrrz/FFmpegBin")!
    static let releasesAPIURL = URL(string: "https://api.github.com/repos/Tyrrrz/FFmpegBin/releases?per_page=10")!
    static let releaseLimit = 6

    #if arch(arm64)
    static let assetName = "ffmpeg-osx-arm64.zip"
    #else
    static let assetName = "ffmpeg-osx-x64.zip"
    #endif

    static func fetchReleases(session: URLSession = .shared) async throws -> [FFmpegRelease] {
        var request = URLRequest(url: releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw FFmpegReleaseError.requestFailed((response as? HTTPURLResponse)?.statusCode)
        }
        return try decodeReleases(from: data)
    }

    static func decodeReleases(from data: Data) throws -> [FFmpegRelease] {
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        let compatible = releases.compactMap { release -> FFmpegRelease? in
            guard !release.draft, !release.prerelease,
                  let asset = release.assets.first(where: { $0.name == assetName }),
                  let digest = asset.digest,
                  digest.hasPrefix("sha256:") else {
                return nil
            }

            return FFmpegRelease(
                version: release.tagName,
                asset: FFmpegAsset(
                    name: asset.name,
                    size: asset.size,
                    sha256: String(digest.dropFirst("sha256:".count)),
                    downloadURL: asset.downloadURL
                )
            )
        }

        guard !compatible.isEmpty else { throw FFmpegReleaseError.noCompatibleRelease }
        return Array(compatible.prefix(releaseLimit))
    }
}

struct FFmpegRelease: Identifiable, Equatable, Sendable {
    var id: String { version }
    let version: String
    let asset: FFmpegAsset
}

struct FFmpegAsset: Equatable, Sendable {
    let name: String
    let size: Int64
    let sha256: String
    let downloadURL: URL
}

enum FFmpegReleaseError: LocalizedError {
    case requestFailed(Int?)
    case noCompatibleRelease

    var errorDescription: String? {
        switch self {
        case let .requestFailed(statusCode):
            if let statusCode { return "Could not fetch FFmpeg releases (HTTP \(statusCode))." }
            return "Could not fetch FFmpeg releases."
        case .noCompatibleRelease:
            return "No verified macOS FFmpeg release was found."
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let size: Int64
    let digest: String?
    let downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case digest
        case downloadURL = "browser_download_url"
    }
}
