import AVFoundation
import AppKit
import Combine
import Foundation

private final class VideoTrimTimeObserver: @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }
}

enum VideoTrimMath {
    static let minimumDuration = 0.1

    static func range(start: Double, end: Double, duration: Double) -> ClosedRange<Double> {
        let safeDuration = max(0, duration)
        let safeStart = min(max(0, start), max(0, safeDuration - minimumDuration))
        let safeEnd = min(max(end, safeStart + minimumDuration), safeDuration)
        return safeStart...safeEnd
    }
}

@MainActor
final class VideoTrimModel: ObservableObject, Identifiable {
    let id = UUID()
    let inputURL: URL
    let player: AVPlayer

    @Published private(set) var pixelSize = CGSize(width: 1920, height: 1080)
    @Published private(set) var inputBytes: Int64 = 0
    @Published private(set) var duration = 0.0
    @Published private(set) var currentTime = 0.0
    @Published private(set) var startTime = 0.0
    @Published private(set) var endTime = 0.0
    @Published private(set) var thumbnails: [NSImage] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    private var timeObserver: VideoTrimTimeObserver?
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

    var formattedStartTime: String { Self.format(time: startTime) }
    var formattedEndTime: String { Self.format(time: endTime) }
    var formattedSelectionDuration: String { Self.format(time: endTime - startTime) }
    var canApply: Bool { endTime - startTime >= VideoTrimMath.minimumDuration }

    func load() async {
        guard isLoading else { return }
        do {
            let asset = AVURLAsset(url: inputURL)
            async let loadedDuration = asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { throw VideoTrimError.missingVideoTrack }
            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).standardized
            pixelSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
            duration = max(0, try await loadedDuration.seconds)
            endTime = duration
            let attributes = try FileManager.default.attributesOfItem(atPath: inputURL.path)
            inputBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            thumbnails = try await VideoTrimThumbnailGenerator.images(asset: asset, duration: duration, count: 10)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func setStartTime(_ time: Double) {
        let range = VideoTrimMath.range(start: time, end: endTime, duration: duration)
        startTime = range.lowerBound
        endTime = range.upperBound
        currentTime = startTime
        seek(to: startTime)
    }

    func setEndTime(_ time: Double) {
        let range = VideoTrimMath.range(start: startTime, end: time, duration: duration)
        startTime = range.lowerBound
        endTime = range.upperBound
        currentTime = endTime
        seek(to: endTime)
    }

    func setCurrentTime(_ time: Double) {
        currentTime = min(max(time, startTime), endTime)
        seek(to: currentTime)
    }

    func setSeeking(_ seeking: Bool) {
        isSeeking = seeking
        if !seeking { seek(to: currentTime) }
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            return
        }
        if currentTime < startTime || currentTime >= endTime - 0.05 {
            currentTime = startTime
            seek(to: startTime)
        }
        player.play()
    }

    func reset() {
        player.pause()
        startTime = 0
        endTime = duration
        currentTime = 0
        seek(to: 0)
    }

    private func observePlayback() {
        timeObserver = VideoTrimTimeObserver(player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                let seconds = time.seconds.isFinite ? time.seconds : self.startTime
                if seconds >= self.endTime {
                    self.player.pause()
                    self.currentTime = self.endTime
                } else {
                    self.currentTime = min(max(seconds, self.startTime), self.endTime)
                }
            }
        })
        playbackObserver = player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.isPlaying = status == .playing }
    }

    private func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private static func format(time: Double) -> String {
        guard time.isFinite else { return "00:00.0" }
        let tenths = max(0, Int((time * 10).rounded(.down)))
        let seconds = tenths / 10
        let hours = seconds / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d.%d", hours, seconds / 60 % 60, seconds % 60, tenths % 10)
            : String(format: "%02d:%02d.%d", seconds / 60, seconds % 60, tenths % 10)
    }
}

private enum VideoTrimError: LocalizedError {
    case missingVideoTrack

    var errorDescription: String? { "Video track could not be read." }
}
