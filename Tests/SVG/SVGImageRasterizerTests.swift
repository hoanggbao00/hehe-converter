import AppKit
import XCTest
@testable import MediaDrop

final class SVGImageRasterizerTests: XCTestCase {
    func testSVGViewportUsesDimensionsViewBoxThenDefault() throws {
        XCTAssertEqual(
            try SVGViewport.size(from: Data("<svg width=\"320\" height=\"180\"></svg>".utf8)),
            CGSize(width: 320, height: 180)
        )
        XCTAssertEqual(
            try SVGViewport.size(from: Data("<svg viewBox=\"0 0 640 360\"></svg>".utf8)),
            CGSize(width: 640, height: 360)
        )
        XCTAssertEqual(
            try SVGViewport.size(from: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)),
            CGSize(width: 512, height: 512)
        )
    }

    @MainActor
    func testSVGRasterizerPreservesTransparentBackground() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let inputURL = directory.appendingPathComponent("transparent.svg")
        let outputURL = directory.appendingPathComponent("transparent.png")
        try Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">
          <circle cx="12" cy="12" r="4" fill="red"/>
        </svg>
        """.utf8).write(to: inputURL)

        try await SVGImageRasterizer.rasterize(inputURL: inputURL, outputURL: outputURL)

        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: outputURL)))
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0, accuracy: 0.01)
    }
}
