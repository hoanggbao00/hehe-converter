import XCTest
@testable import MediaDrop

final class ConversionLimiterTests: XCTestCase {
    func testConversionLimiterCapsConcurrentWork() async {
        let limiter = ConversionLimiter()
        let activity = ConversionActivity()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    await limiter.acquire(limit: 2)
                    await activity.start()
                    try? await Task.sleep(for: .milliseconds(20))
                    await activity.finish()
                    await limiter.release()
                }
            }
        }

        let peak = await activity.peakCount()
        XCTAssertEqual(peak, 2)
    }
}

private actor ConversionActivity {
    private var current = 0
    private var peak = 0

    func start() {
        current += 1
        peak = max(peak, current)
    }

    func finish() {
        current -= 1
    }

    func peakCount() -> Int { peak }
}
