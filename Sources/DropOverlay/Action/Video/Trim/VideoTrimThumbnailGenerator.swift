import AVFoundation
import AppKit

private final class VideoTrimSendableImageGenerator: @unchecked Sendable {
    let value: AVAssetImageGenerator

    init(_ value: AVAssetImageGenerator) {
        self.value = value
    }
}

@MainActor
enum VideoTrimThumbnailGenerator {
    static func images(asset: AVAsset, duration: Double, count: Int) async throws -> [NSImage] {
        guard duration > 0, count > 0 else { return [] }
        let generator = VideoTrimSendableImageGenerator(AVAssetImageGenerator(asset: asset))
        generator.value.appliesPreferredTrackTransform = true
        generator.value.maximumSize = CGSize(width: 160, height: 90)
        generator.value.requestedTimeToleranceBefore = .zero
        generator.value.requestedTimeToleranceAfter = .zero
        let times = (0..<count).map {
            CMTime(seconds: duration * (Double($0) + 0.5) / Double(count), preferredTimescale: 600)
        }

        var images: [NSImage] = []
        for time in times {
            let image = try await generator.value.image(at: time).image
            images.append(NSImage(cgImage: image, size: .zero))
        }
        return images
    }
}
