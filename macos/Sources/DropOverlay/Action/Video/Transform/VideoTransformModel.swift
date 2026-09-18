import AVFoundation
import Combine
import Foundation
import SwiftUI

private final class VideoTransformTimeObserver: @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }
}

struct VideoTransformSettings: Equatable {
    let unit: ImageDimensionUnit
    let width: Double
    let height: Double
    let flipsHorizontally: Bool
    let flipsVertically: Bool
}

@MainActor
final class VideoTransformModel: ObservableObject, Identifiable {
    let id = UUID()
    let inputURL: URL
    let player: AVPlayer

    @Published private(set) var unit: ImageDimensionUnit = .percent
    @Published private(set) var width = 100.0
    @Published private(set) var height = 100.0
    @Published var keepsAspectRatio = true
    @Published var flipsHorizontally = false
    @Published var flipsVertically = false
    @Published private(set) var pixelSize = CGSize(width: 1920, height: 1080)
    @Published private(set) var inputBytes: Int64 = 0
    @Published private(set) var duration = 0.0
    @Published private(set) var currentTime = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = true
    @Published var isApplying = false
    @Published var errorMessage: String?

    private var timeObserver: VideoTransformTimeObserver?
    private var playbackObserver: AnyCancellable?
    private var isSeeking = false
    private var lockedAspectRatio: Double?

    init(inputURL: URL) {
        self.inputURL = inputURL
        player = AVPlayer(url: inputURL)
        observePlayback()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver.value) }
    }

    var settings: VideoTransformSettings {
        VideoTransformSettings(
            unit: unit,
            width: width,
            height: height,
            flipsHorizontally: flipsHorizontally,
            flipsVertically: flipsVertically
        )
    }

    var outputPixelSize: CGSize {
        Self.outputPixelSize(for: pixelSize, settings: settings)
    }

    var formattedInputSize: String {
        ByteCountFormatter.string(fromByteCount: inputBytes, countStyle: .file)
    }

    var formattedCurrentTime: String { Self.format(time: currentTime) }
    var formattedDuration: String { Self.format(time: duration) }

    var canApply: Bool {
        outputPixelSize != pixelSize || flipsHorizontally || flipsVertically
    }

    nonisolated static func outputPixelSize(for sourcePixelSize: CGSize, settings: VideoTransformSettings) -> CGSize {
        guard sourcePixelSize.width > 0, sourcePixelSize.height > 0 else {
            return CGSize(width: 2, height: 2)
        }
        let boundingSize: CGSize
        switch settings.unit {
        case .percent:
            boundingSize = CGSize(
                width: sourcePixelSize.width * settings.width / 100,
                height: sourcePixelSize.height * settings.height / 100
            )
        case .pixels:
            boundingSize = CGSize(width: settings.width, height: settings.height)
        }
        return CGSize(
            width: even(boundingSize.width),
            height: even(boundingSize.height)
        )
    }

    func load() async {
        guard isLoading else { return }
        do {
            let asset = AVURLAsset(url: inputURL)
            async let loadedDuration = asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { throw VideoTransformError.missingVideoTrack }
            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformed = CGRect(origin: .zero, size: naturalSize)
                .applying(preferredTransform)
                .standardized
            pixelSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
            duration = max(0, try await loadedDuration.seconds)
            let attributes = try FileManager.default.attributesOfItem(atPath: inputURL.path)
            inputBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            if VideoCropModel.shouldRestartPlayback(currentTime: currentTime, duration: duration) {
                currentTime = 0
                seek(to: 0)
            }
            player.play()
        }
    }

    func setSeeking(_ seeking: Bool) {
        isSeeking = seeking
        if !seeking { seek(to: currentTime) }
    }

    func setCurrentTime(_ time: Double) {
        currentTime = min(max(time, 0), duration)
        if isSeeking { seek(to: currentTime) }
    }

    func reset() {
        unit = .percent
        width = 100
        height = 100
        keepsAspectRatio = true
        lockedAspectRatio = nil
        flipsHorizontally = false
        flipsVertically = false
        errorMessage = nil
    }

    func applyUnit(_ newUnit: ImageDimensionUnit) {
        guard unit != newUnit else { return }
        if newUnit == .pixels {
            width = round(pixelSize.width * width / 100)
            height = round(pixelSize.height * height / 100)
        } else {
            width = round(width / pixelSize.width * 100)
            height = round(height / pixelSize.height * 100)
        }
        unit = newUnit
    }

    func setKeepsAspectRatio(_ isLocked: Bool) {
        guard keepsAspectRatio != isLocked else { return }
        if isLocked { lockedAspectRatio = currentAspectRatio }
        keepsAspectRatio = isLocked
    }

    func setWidth(_ newWidth: Double) {
        let nextWidth = clamped(newWidth, axis: .horizontal)
        guard keepsAspectRatio else {
            width = nextWidth
            return
        }
        let nextHeight: Double = switch unit {
        case .percent:
            rounded(nextWidth * pixelSize.width / pixelSize.height / aspectRatio)
        case .pixels:
            rounded(nextWidth / aspectRatio)
        }
        guard range(for: .vertical).contains(nextHeight) else { return }
        width = nextWidth
        height = nextHeight
    }

    func setHeight(_ newHeight: Double) {
        let nextHeight = clamped(newHeight, axis: .vertical)
        guard keepsAspectRatio else {
            height = nextHeight
            return
        }
        let nextWidth: Double = switch unit {
        case .percent:
            rounded(nextHeight * pixelSize.height / pixelSize.width * aspectRatio)
        case .pixels:
            rounded(nextHeight * aspectRatio)
        }
        guard range(for: .horizontal).contains(nextWidth) else { return }
        width = nextWidth
        height = nextHeight
    }

    func resizePreview(handle: ResizeHandlePosition, from startSize: CGSize, translation: CGSize, in videoRectSize: CGSize) {
        guard videoRectSize.width > 0, videoRectSize.height > 0 else { return }
        let widthDelta = Double(handle.horizontalEdge * translation.width / videoRectSize.width * pixelSize.width)
        let heightDelta = Double(handle.verticalEdge * translation.height / videoRectSize.height * pixelSize.height)
        let nextWidth = Double(startSize.width) + widthDelta
        let nextHeight = Double(startSize.height) + heightDelta

        if keepsAspectRatio {
            if abs(widthDelta) >= abs(heightDelta) {
                setWidth(value(forPixels: nextWidth, axis: .horizontal))
            } else {
                setHeight(value(forPixels: nextHeight, axis: .vertical))
            }
            return
        }

        width = clamped(value(forPixels: nextWidth, axis: .horizontal), axis: .horizontal)
        height = clamped(value(forPixels: nextHeight, axis: .vertical), axis: .vertical)
    }

    func previewRect(in videoRect: CGRect) -> CGRect {
        let output = outputPixelSize
        let widthFraction = min(max(output.width / max(pixelSize.width, 1), 0.01), 1)
        let heightFraction = min(max(output.height / max(pixelSize.height, 1), 0.01), 1)
        let size = CGSize(width: videoRect.width * widthFraction, height: videoRect.height * heightFraction)
        return CGRect(
            x: videoRect.midX - size.width / 2,
            y: videoRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func range(for axis: Axis) -> ClosedRange<Double> {
        switch unit {
        case .percent:
            1...100
        case .pixels:
            2...32_768
        }
    }

    func applyTransform() async throws -> URL {
        player.pause()
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        return try await VideoTransformFFmpegRunner.run(inputURL: inputURL, settings: settings, sourcePixelSize: pixelSize)
    }

    private func observePlayback() {
        timeObserver = VideoTransformTimeObserver(player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                self.currentTime = min(max(0, time.seconds.isFinite ? time.seconds : 0), self.duration)
            }
        })
        playbackObserver = player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.isPlaying = status == .playing }
    }

    private func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func clamped(_ value: Double, axis: Axis) -> Double {
        let range = range(for: axis)
        return min(max(rounded(value), range.lowerBound), range.upperBound)
    }

    private func rounded(_ value: Double) -> Double { value.rounded() }

    private func value(forPixels pixels: Double, axis: Axis) -> Double {
        switch unit {
        case .percent:
            let length = axis == .horizontal ? pixelSize.width : pixelSize.height
            return pixels / max(length, 1) * 100
        case .pixels:
            return pixels
        }
    }

    private var aspectRatio: Double {
        lockedAspectRatio ?? max(pixelSize.width, 1) / max(pixelSize.height, 1)
    }

    private var currentAspectRatio: Double {
        let size = outputPixelSize
        return max(size.width, 1) / max(size.height, 1)
    }

    nonisolated private static func even(_ value: Double) -> Double {
        max(2, (value.rounded() / 2).rounded(.down) * 2)
    }

    private static func format(time: Double) -> String {
        guard time.isFinite else { return "00:00" }
        let seconds = max(0, Int(time.rounded(.down)))
        let hours = seconds / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private enum VideoTransformError: LocalizedError {
    case missingVideoTrack

    var errorDescription: String? { "Video track could not be read." }
}
