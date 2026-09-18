import AVFoundation
import AppKit
import Combine
import SwiftUI

private final class VideoCropTimeObserver: @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }
}

@MainActor
final class VideoCropModel: ObservableObject, Identifiable {
    let id = UUID()
    let inputURL: URL
    let player: AVPlayer

    @Published var unit: CropDimensionUnit = .percent
    @Published var aspectRatio: CropAspectRatio = .original
    @Published private(set) var width = 100.0
    @Published private(set) var height = 100.0
    @Published var cropCenter = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var pixelSize = CGSize(width: 1920, height: 1080)
    @Published private(set) var inputBytes: Int64 = 0
    @Published private(set) var duration = 0.0
    @Published private(set) var currentTime = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = true
    @Published var isApplying = false
    @Published var errorMessage: String?

    private var timeObserver: VideoCropTimeObserver?
    private var playbackObserver: AnyCancellable?
    private var isSeeking = false

    init(inputURL: URL) {
        self.inputURL = inputURL
        player = AVPlayer(url: inputURL)
        observePlayback()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver.value) }
    }

    var formattedInputSize: String {
        ByteCountFormatter.string(fromByteCount: inputBytes, countStyle: .file)
    }

    var formattedCurrentTime: String { Self.format(time: currentTime) }
    var formattedDuration: String { Self.format(time: duration) }

    nonisolated static func shouldRestartPlayback(currentTime: Double, duration: Double) -> Bool {
        duration > 0 && currentTime >= duration - 0.05
    }

    func load() async {
        guard isLoading else { return }
        do {
            let asset = AVURLAsset(url: inputURL)
            async let loadedDuration = asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { throw VideoCropError.missingVideoTrack }
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
            if Self.shouldRestartPlayback(currentTime: currentTime, duration: duration) {
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
        aspectRatio = .original
        width = 100
        height = 100
        cropCenter = CGPoint(x: 0.5, y: 0.5)
        errorMessage = nil
    }

    func applyUnit(_ newUnit: CropDimensionUnit) {
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

    func applyAspectRatio(_ ratio: CropAspectRatio) {
        aspectRatio = ratio
        guard ratio.ratio(for: pixelSize) != nil else { return }
        setWidth(width)
    }

    func setWidth(_ value: Double) {
        setCropSize(widthPixels: pixels(for: value, axis: .horizontal), changedAxis: .horizontal)
    }

    func setHeight(_ value: Double) {
        setCropSize(heightPixels: pixels(for: value, axis: .vertical), changedAxis: .vertical)
    }

    func moveCrop(from start: CGPoint, translation: CGSize) {
        let widthFraction = fraction(for: width, axis: .horizontal)
        let heightFraction = fraction(for: height, axis: .vertical)
        cropCenter = CGPoint(
            x: min(max(start.x + translation.width, widthFraction / 2), 1 - widthFraction / 2),
            y: min(max(start.y + translation.height, heightFraction / 2), 1 - heightFraction / 2)
        )
    }

    func resizeCrop(handle: CropHandlePosition, from startRect: CGRect, translation: CGSize) {
        var minX = startRect.minX
        var maxX = startRect.maxX
        var minY = startRect.minY
        var maxY = startRect.maxY
        let minimum: CGFloat = 0.03

        if handle.horizontalEdge < 0 { minX = min(max(minX + translation.width, 0), maxX - minimum) }
        if handle.horizontalEdge > 0 { maxX = max(min(maxX + translation.width, 1), minX + minimum) }
        if handle.verticalEdge < 0 { minY = min(max(minY + translation.height, 0), maxY - minimum) }
        if handle.verticalEdge > 0 { maxY = max(min(maxY + translation.height, 1), minY + minimum) }

        if let ratio = aspectRatio.ratio(for: pixelSize) {
            let widthFraction = maxX - minX
            let heightFraction = maxY - minY
            if abs(translation.width) * pixelSize.width >= abs(translation.height) * pixelSize.height {
                let newHeight = widthFraction * pixelSize.width / ratio / pixelSize.height
                if handle.verticalEdge < 0 { minY = maxY - newHeight } else { maxY = minY + newHeight }
            } else {
                let newWidth = heightFraction * pixelSize.height * ratio / pixelSize.width
                if handle.horizontalEdge < 0 { minX = maxX - newWidth } else { maxX = minX + newWidth }
            }
            let fitted = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            minX = fitted.minX
            maxX = fitted.maxX
            minY = fitted.minY
            maxY = fitted.maxY
        }

        setDisplayedDimensions(widthPixels: pixelSize.width * (maxX - minX), heightPixels: pixelSize.height * (maxY - minY))
        cropCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    func normalizedCropRect() -> CGRect {
        let widthFraction = fraction(for: width, axis: .horizontal)
        let heightFraction = fraction(for: height, axis: .vertical)
        return CGRect(
            x: cropCenter.x - widthFraction / 2,
            y: cropCenter.y - heightFraction / 2,
            width: widthFraction,
            height: heightFraction
        )
    }

    func cropRect(in videoRect: CGRect) -> CGRect {
        let normalized = normalizedCropRect()
        return CGRect(
            x: videoRect.minX + normalized.minX * videoRect.width,
            y: videoRect.minY + normalized.minY * videoRect.height,
            width: normalized.width * videoRect.width,
            height: normalized.height * videoRect.height
        )
    }

    func pixelCropRect() -> CGRect {
        let rect = normalizedCropRect()
        let x = even(floor(rect.minX * pixelSize.width), maximum: pixelSize.width - 2)
        let y = even(floor(rect.minY * pixelSize.height), maximum: pixelSize.height - 2)
        let width = even(round(rect.width * pixelSize.width), maximum: pixelSize.width - x)
        let height = even(round(rect.height * pixelSize.height), maximum: pixelSize.height - y)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func applyCrop() async throws -> URL {
        player.pause()
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        return try await VideoCropFFmpegRunner.run(inputURL: inputURL, cropRect: pixelCropRect())
    }

    private func observePlayback() {
        timeObserver = VideoCropTimeObserver(player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
            }
        })
        playbackObserver = player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.isPlaying = status == .playing }
    }

    private func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func setCropSize(widthPixels: CGFloat? = nil, heightPixels: CGFloat? = nil, changedAxis: Axis) {
        var nextWidth = min(max(widthPixels ?? pixels(for: width, axis: .horizontal), 2), pixelSize.width)
        var nextHeight = min(max(heightPixels ?? pixels(for: height, axis: .vertical), 2), pixelSize.height)
        if let ratio = aspectRatio.ratio(for: pixelSize) {
            if changedAxis == .horizontal {
                nextHeight = nextWidth / ratio
                if nextHeight > pixelSize.height { nextHeight = pixelSize.height; nextWidth = nextHeight * ratio }
            } else {
                nextWidth = nextHeight * ratio
                if nextWidth > pixelSize.width { nextWidth = pixelSize.width; nextHeight = nextWidth / ratio }
            }
        }
        setDisplayedDimensions(widthPixels: nextWidth, heightPixels: nextHeight)
        clampCropCenter()
    }

    private func setDisplayedDimensions(widthPixels: CGFloat, heightPixels: CGFloat) {
        if unit == .percent {
            width = Double(widthPixels / pixelSize.width * 100)
            height = Double(heightPixels / pixelSize.height * 100)
        } else {
            width = Double(round(widthPixels))
            height = Double(round(heightPixels))
        }
    }

    private func fraction(for value: Double, axis: Axis) -> CGFloat {
        let length = axis == .horizontal ? pixelSize.width : pixelSize.height
        return min(max(unit == .percent ? CGFloat(value / 100) : CGFloat(value) / length, 0.01), 1)
    }

    private func pixels(for value: Double, axis: Axis) -> CGFloat {
        let length = axis == .horizontal ? pixelSize.width : pixelSize.height
        return unit == .percent ? length * CGFloat(value / 100) : CGFloat(value)
    }

    private func clampCropCenter() {
        let halfWidth = fraction(for: width, axis: .horizontal) / 2
        let halfHeight = fraction(for: height, axis: .vertical) / 2
        cropCenter = CGPoint(
            x: min(max(cropCenter.x, halfWidth), 1 - halfWidth),
            y: min(max(cropCenter.y, halfHeight), 1 - halfHeight)
        )
    }

    private func even(_ value: CGFloat, maximum: CGFloat) -> CGFloat {
        max(2, min(floor(value / 2) * 2, floor(maximum / 2) * 2))
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

private enum VideoCropError: LocalizedError {
    case missingVideoTrack

    var errorDescription: String? { "Video track could not be read." }
}
