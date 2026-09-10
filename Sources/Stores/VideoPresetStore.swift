import AppKit

@MainActor
final class VideoPresetStore: ObservableObject {
    @Published private(set) var presets: [StoredVideoPreset] = []
    @Published private(set) var errorMessage: String?

    private let storage: PresetStorage

    init(storage: PresetStorage = PresetStorage()) {
        self.storage = storage
        reload()
    }

    func add(name: String, outputFormat: VideoOutputFormat, options: VideoEncodingOptions?) {
        do {
            try storage.save(VideoPreset(name: name, outputFormat: outputFormat, options: options))
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(
        _ storedPreset: StoredVideoPreset,
        name: String,
        outputFormat: VideoOutputFormat,
        options: VideoEncodingOptions?
    ) {
        do {
            let preset = VideoPreset(
                id: storedPreset.preset.id,
                name: name,
                outputFormat: outputFormat,
                options: options
            )
            try storage.update(storedPreset, with: preset)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() {
        do {
            presets = try storage.loadVideoPresets()
            errorMessage = nil
        } catch {
            presets = []
            errorMessage = error.localizedDescription
        }
    }

    func openVideoPresetFolder() {
        let directory = storage.directory(for: .video)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func delete(_ storedPreset: StoredVideoPreset) {
        do {
            try storage.delete(storedPreset)
            presets.removeAll { $0.id == storedPreset.id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
