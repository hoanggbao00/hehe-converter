import AVFoundation
import Foundation

struct VideoCompressSettings: Equatable {
    let unit: ImageDimensionUnit
    let width: Double
    let height: Double
    let fps: Double
    let bitrateKbps: Int
    let quality: Int
    let mutesAudio: Bool
    let removesMetadata: Bool
}

@MainActor
final class VideoCompressModel: ObservableObject {
    let preview: VideoTransformModel

    @Published var fps = 30.0
    @Published var bitrateKbps = 2_500.0
    @Published var quality = 80.0
    @Published var mutesAudio = false
    @Published var removesMetadata = true

    private var defaultFPS = 30.0
    private var defaultBitrateKbps = 2_500.0

    init(inputURL: URL) {
        preview = VideoTransformModel(inputURL: inputURL)
    }

    var settings: VideoCompressSettings {
        VideoCompressSettings(
            unit: preview.unit,
            width: preview.width,
            height: preview.height,
            fps: min(max(fps.rounded(), 1), 120),
            bitrateKbps: Int(min(max(bitrateKbps.rounded(), 100), 500_000)),
            quality: Int(min(max(quality.rounded(), 1), 100)),
            mutesAudio: mutesAudio,
            removesMetadata: removesMetadata
        )
    }

    func reset() {
        preview.reset()
        fps = defaultFPS
        bitrateKbps = defaultBitrateKbps
        quality = 80
        mutesAudio = false
        removesMetadata = true
    }

    func load() async {
        async let previewLoad: Void = preview.load()
        async let sourceInfo = Self.sourceInfo(for: preview.inputURL)
        await previewLoad
        let info = await sourceInfo
        defaultFPS = info.fps
        defaultBitrateKbps = info.bitrateKbps
        fps = info.fps
        bitrateKbps = info.bitrateKbps
    }

    nonisolated static func normalizedDefaults(fps: Double?, bitrateKbps: Double?) -> VideoCompressSourceInfo {
        VideoCompressSourceInfo(
            fps: min(max((fps ?? 30).rounded(), 1), 120),
            bitrateKbps: min(max((bitrateKbps ?? 2_500).rounded(), 100), 50_000)
        )
    }

    private nonisolated static func sourceInfo(for inputURL: URL) async -> VideoCompressSourceInfo {
        do {
            let asset = AVURLAsset(url: inputURL)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return normalizedDefaults(fps: nil, bitrateKbps: nil) }
            let fps = try await track.load(.nominalFrameRate)
            let bitrate = try await track.load(.estimatedDataRate)
            return normalizedDefaults(
                fps: Double(fps),
                bitrateKbps: Double(bitrate) / 1_000
            )
        } catch {
            return normalizedDefaults(fps: nil, bitrateKbps: nil)
        }
    }
}

struct VideoCompressSourceInfo: Equatable, Sendable {
    let fps: Double
    let bitrateKbps: Double
}
