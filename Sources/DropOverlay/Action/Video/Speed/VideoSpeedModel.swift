import AVFoundation
import Combine
import Foundation

private final class VideoSpeedTimeObserver: @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }
}

enum VideoSpeedMath {
    static let range = 0.25...15.0

    static func clamp(_ speed: Double) -> Double {
        min(max(speed.isFinite ? speed : 1, range.lowerBound), range.upperBound)
    }

    static func previewTime(_ sourceTime: Double, speed: Double) -> Double {
        sourceTime / clamp(speed)
    }

    static func shortLabel(for speed: Double) -> String {
        String(format: "%.2g", locale: Locale(identifier: "en_US_POSIX"), clamp(speed)).replacingOccurrences(of: ".", with: "_") + "x"
    }
}

@MainActor
final class VideoSpeedModel: ObservableObject, Identifiable {
    static let speedRange = VideoSpeedMath.range

    let id = UUID()
    let inputURL: URL
    let player: AVPlayer

    @Published var draftSpeed = 1.0 {
        didSet {
            let clamped = VideoSpeedMath.clamp(draftSpeed)
            if clamped != draftSpeed { draftSpeed = clamped }
        }
    }
    @Published private(set) var speed = 1.0
    @Published var muteAudio = false {
        didSet { player.isMuted = muteAudio }
    }
    @Published private(set) var pixelSize = CGSize(width: 1920, height: 1080)
    @Published private(set) var inputBytes: Int64 = 0
    @Published private(set) var duration = 0.0
    @Published private(set) var currentTime = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    private var timeObserver: VideoSpeedTimeObserver?
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

    var formattedCurrentTime: String { Self.format(time: VideoSpeedMath.previewTime(currentTime, speed: speed)) }
    var formattedDuration: String { Self.format(time: VideoSpeedMath.previewTime(duration, speed: speed)) }
    func load() async {
        guard isLoading else { return }
        do {
            let asset = AVURLAsset(url: inputURL)
            async let loadedDuration = asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { throw VideoSpeedError.missingVideoTrack }
            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).standardized
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
            player.playImmediately(atRate: Float(speed))
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

    func resetSpeed() {
        draftSpeed = 1
        commitSpeed()
    }

    func commitSpeed() {
        let committedSpeed = VideoSpeedMath.clamp(draftSpeed)
        draftSpeed = committedSpeed
        speed = committedSpeed
        if isPlaying { player.rate = Float(committedSpeed) }
    }

    var canApply: Bool {
        speed != 1 || muteAudio
    }

    private func observePlayback() {
        timeObserver = VideoSpeedTimeObserver(player.addPeriodicTimeObserver(
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

    private static func format(time: Double) -> String {
        guard time.isFinite else { return "00:00" }
        let seconds = max(0, Int(time.rounded(.down)))
        let hours = seconds / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private enum VideoSpeedError: LocalizedError {
    case missingVideoTrack

    var errorDescription: String? { "Video track could not be read." }
}
