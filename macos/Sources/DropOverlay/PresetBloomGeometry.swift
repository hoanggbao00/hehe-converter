import Foundation

struct PresetBloomGeometry {
    let count: Int
    let innerRadius: Double
    let outerRadius: Double

    func selectedIndex(deltaX: Double, deltaY: Double) -> Int? {
        guard count > 0 else { return nil }

        let distance = hypot(deltaX, deltaY)
        guard (innerRadius...outerRadius).contains(distance) else { return nil }

        let degrees = normalizedDegrees(90 - atan2(deltaY, deltaX) * 180 / .pi)
        let slot = 360 / Double(count)
        return Int((degrees + slot / 2) / slot) % count
    }

    private func normalizedDegrees(_ value: Double) -> Double {
        let normalized = value.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }
}
