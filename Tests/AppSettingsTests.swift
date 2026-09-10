import XCTest
@testable import MediaDrop

final class AppSettingsTests: XCTestCase {
    func testDefaultsEnableFinderInSpecifiedApps() {
        let settings = AppSettings()

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.triggerScope, .specifiedApps)
        XCTAssertEqual(settings.specifiedApps, [AllowedApps.finder])
        XCTAssertTrue(settings.specifiedApps[0].isEnabled)
        XCTAssertEqual(settings.specifiedApps[0].bundleIdentifier, "com.apple.finder")
    }

    func testFFmpegReleaseDecoderUsesLatestCompatibleTyrrrzReleases() throws {
        let assetName = FFmpegDistribution.assetName
        let data = Data("""
        [
          {
            "tag_name": "9.0.1",
            "draft": false,
            "prerelease": false,
            "assets": [{
              "name": "\(assetName)",
              "size": 123,
              "digest": "sha256:abcdef",
              "browser_download_url": "https://example.com/9.0.1.zip"
            }]
          },
          {
            "tag_name": "9.1-beta",
            "draft": false,
            "prerelease": true,
            "assets": [{
              "name": "\(assetName)",
              "size": 456,
              "digest": "sha256:ignored",
              "browser_download_url": "https://example.com/beta.zip"
            }]
          },
          {
            "tag_name": "8.1.2",
            "draft": false,
            "prerelease": false,
            "assets": [{
              "name": "\(assetName)",
              "size": 789,
              "digest": "sha256:123456",
              "browser_download_url": "https://example.com/8.1.2.zip"
            }]
          }
        ]
        """.utf8)

        let releases = try FFmpegDistribution.decodeReleases(from: data)

        XCTAssertEqual(releases.map(\.version), ["9.0.1", "8.1.2"])
        XCTAssertEqual(releases.first?.asset.name, assetName)
        XCTAssertEqual(releases.first?.asset.size, 123)
        XCTAssertEqual(releases.first?.asset.sha256, "abcdef")
        XCTAssertEqual(releases.first?.asset.downloadURL.absoluteString, "https://example.com/9.0.1.zip")
        XCTAssertEqual(FFmpegDistribution.repository, "Tyrrrz/FFmpegBin")
        XCTAssertEqual(FFmpegDistribution.releaseLimit, 6)
        XCTAssertEqual(
            FFmpegDistribution.releasesAPIURL.absoluteString,
            "https://api.github.com/repos/Tyrrrz/FFmpegBin/releases?per_page=10"
        )
        XCTAssertTrue(FFmpegInstall.binDirectory.path.hasSuffix(".local/com.hoanggbao.MediaDrop/bin"))
    }

    func testFFmpegReleaseDecoderRejectsAssetWithoutChecksum() {
        let data = Data("""
        [{
          "tag_name": "9.0.1",
          "draft": false,
          "prerelease": false,
          "assets": [{
            "name": "\(FFmpegDistribution.assetName)",
            "size": 123,
            "digest": null,
            "browser_download_url": "https://example.com/ffmpeg.zip"
          }]
        }]
        """.utf8)

        XCTAssertThrowsError(try FFmpegDistribution.decodeReleases(from: data))
    }

    func testFFmpegOnboardingOnlyShowsOnceWhenFFmpegIsMissing() {
        XCTAssertTrue(FFmpegOnboarding.shouldShow(isInstalled: false, wasPresented: false))
        XCTAssertFalse(FFmpegOnboarding.shouldShow(isInstalled: true, wasPresented: false))
        XCTAssertFalse(FFmpegOnboarding.shouldShow(isInstalled: false, wasPresented: true))
    }
}
