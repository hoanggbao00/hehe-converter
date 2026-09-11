import XCTest
@testable import MediaDrop

final class DropOverlayTests: XCTestCase {
    func testPresetBloomSelectionUsesTopAsFirstSlot() {
        let geometry = PresetBloomGeometry(count: 5, innerRadius: 43, outerRadius: 112)

        XCTAssertEqual(geometry.selectedIndex(deltaX: 0, deltaY: 80), 0)
        XCTAssertEqual(geometry.selectedIndex(deltaX: 80, deltaY: 0), 1)
        XCTAssertEqual(geometry.selectedIndex(deltaX: 0, deltaY: -80), 3)
        XCTAssertNil(geometry.selectedIndex(deltaX: 0, deltaY: 20))
        XCTAssertNil(geometry.selectedIndex(deltaX: 0, deltaY: 130))
    }

    func testIndeterminateProgressThumbMovesBackAndForth() {
        XCTAssertEqual(AccentProgressBar.indeterminateOffset(at: 0, travel: 100), 0, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateOffset(at: 0.4, travel: 100), 50, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateOffset(at: 0.8, travel: 100), 100, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateOffset(at: 1.2, travel: 100), 50, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateWidth(at: 0, trackWidth: 200), 32, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateWidth(at: 0.4, trackWidth: 200), 80, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateWidth(at: 0.8, trackWidth: 200), 32, accuracy: 0.001)
        XCTAssertEqual(AccentProgressBar.indeterminateWidth(at: 1.2, trackWidth: 200), 80, accuracy: 0.001)
    }
}
