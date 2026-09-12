import AVFoundation
import AppKit
import Combine
import SwiftUI

private final class VideoSnapshotTimeObserver: @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }
}

enum VideoSnapshotFormat: String, CaseIterable, Identifiable {
    case jpg = "JPG"
    case png = "PNG"
    case tiff = "TIFF"

    var id: Self { self }

    var fileExtension: String { rawValue.lowercased() }

    var bitmapFileType: NSBitmapImageRep.FileType {
        switch self {
        case .jpg: .jpeg
        case .png: .png
        case .tiff: .tiff
        }
    }

    var bitmapProperties: [NSBitmapImageRep.PropertyKey: Any] {
        switch self {
        case .jpg: [.compressionFactor: 0.92]
        case .png, .tiff: [:]
        }
    }
}

@MainActor
final class VideoSnapshotModel: ObservableObject, Identifiable {
    let id = UUID()
    let inputURL: URL
    let player: AVPlayer

    @Published var format: VideoSnapshotFormat = .jpg
    @Published private(set) var pixelSize = CGSize(width: 1920, height: 1080)
    @Published private(set) var inputBytes: Int64 = 0
    @Published private(set) var duration = 0.0
    @Published private(set) var currentTime = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = true
    @Published var isApplying = false
    @Published var errorMessage: String?

    private var timeObserver: VideoSnapshotTimeObserver?
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

    func load() async {
        guard isLoading else { return }
        do {
            let asset = AVURLAsset(url: inputURL)
            async let loadedDuration = asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { throw VideoSnapshotError.missingVideoTrack }
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

    func applySnapshot() async throws -> URL {
        player.pause()
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        return try await VideoSnapshotRunner.run(inputURL: inputURL, time: currentTime, format: format)
    }

    private func observePlayback() {
        timeObserver = VideoSnapshotTimeObserver(player.addPeriodicTimeObserver(
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

private enum VideoSnapshotError: LocalizedError {
    case missingVideoTrack

    var errorDescription: String? { "Video track could not be read." }
}
