import AppKit

@MainActor
final class AudioPresetStore: ObservableObject {
    @Published private(set) var presets: [StoredAudioPreset] = []
    @Published private(set) var errorMessage: String?

    private let storage: PresetStorage

    init(storage: PresetStorage = PresetStorage()) {
        self.storage = storage
        reload()
    }

    func add(name: String, outputFormat: VideoOutputFormat, options: VideoEncodingOptions?) {
        do {
            try storage.saveAudio(VideoPreset(name: name, outputFormat: outputFormat, options: options))
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(_ storedPreset: StoredAudioPreset, name: String, outputFormat: VideoOutputFormat, options: VideoEncodingOptions?) {
        do {
            try storage.update(
                storedPreset,
                with: VideoPreset(id: storedPreset.id, name: name, outputFormat: outputFormat, options: options)
            )
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() {
        do {
            presets = try storage.loadAudioPresets()
            errorMessage = nil
        } catch {
            presets = []
            errorMessage = error.localizedDescription
        }
    }

    func openAudioPresetFolder() {
        let directory = storage.directory(for: .audio)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func delete(_ storedPreset: StoredAudioPreset) {
        do {
            try storage.delete(storedPreset)
            presets.removeAll { $0.id == storedPreset.id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
