import XCTest
@testable import HeheConverter

final class AppUpdateTests: XCTestCase {
    func testSemanticVersionComparison() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("0.9.9")), try XCTUnwrap(AppVersion("v0.10.0")))
        XCTAssertEqual(AppVersion("1.2.3"), AppVersion("v1.2.3"))
        XCTAssertNil(AppVersion("1.2"))
    }

    func testReleaseSelectsVerifiedDMG() throws {
        let data = Data("""
        {
          "tag_name": "v1.2.3",
          "html_url": "https://github.com/hoanggbao00/hehe-converter/releases/tag/v1.2.3",
          "draft": false,
          "prerelease": false,
          "body": "## Changes\\n- Added update banner",
          "assets": [{
            "name": "HeheConverter-v1.2.3.dmg",
            "digest": "sha256:ABCDEF",
            "size": 123456,
            "browser_download_url": "https://example.com/HeheConverter-v1.2.3.dmg"
          }]
        }
        """.utf8)

        let release = try AppUpdateService.decodeRelease(from: data)

        XCTAssertEqual(release.version, "1.2.3")
        XCTAssertEqual(release.sha256, "abcdef")
        XCTAssertEqual(release.size, 123456)
        XCTAssertEqual(release.downloadURL.absoluteString, "https://example.com/HeheConverter-v1.2.3.dmg")
    }

    func testReleaseNotesDecodeBody() throws {
        let data = Data("""
        {
          "tag_name": "v1.2.3",
          "html_url": "https://github.com/hoanggbao00/hehe-converter/releases/tag/v1.2.3",
          "draft": false,
          "prerelease": false,
          "body": "## Changes\\n- Added update banner",
          "assets": []
        }
        """.utf8)

        let notes = try AppUpdateService.decodeReleaseNotes(from: data)

        XCTAssertEqual(notes.version, "1.2.3")
        XCTAssertEqual(notes.body, "## Changes\n- Added update banner")
        XCTAssertEqual(notes.pageURL.absoluteString, "https://github.com/hoanggbao00/hehe-converter/releases/tag/v1.2.3")
    }
}
