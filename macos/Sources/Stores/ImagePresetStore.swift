import AppKit
import Foundation

@MainActor
final class ImagePresetStore: ObservableObject {
    @Published private(set) var presets: [StoredImagePreset] = []
    @Published private(set) var errorMessage: String?

    private let storage: PresetStorage

    init(storage: PresetStorage = PresetStorage()) {
        self.storage = storage
        reload()
    }

    func add(
        name: String,
        outputFormat: ImageOutputFormat,
        resize: ImageResize?,
        options: ImageEncodingOptions?
    ) {
        do {
            let preset = ImagePreset(
                name: name,
                outputFormat: outputFormat,
                resize: resize,
                options: options
            )
            try storage.save(preset)
            reload()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() {
        do {
            presets = try storage.loadImagePresets()
            errorMessage = nil
        } catch {
            presets = []
            errorMessage = error.localizedDescription
        }
    }

    func openImagePresetFolder() {
        try? FileManager.default.createDirectory(
            at: storage.directory(for: .image),
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(storage.directory(for: .image))
    }

    func delete(_ storedPreset: StoredImagePreset) {
        do {
            try storage.delete(storedPreset)
            presets.removeAll { $0.id == storedPreset.id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(
        _ storedPreset: StoredImagePreset,
        name: String,
        outputFormat: ImageOutputFormat,
        resize: ImageResize?,
        options: ImageEncodingOptions?
    ) {
        do {
            let preset = ImagePreset(
                id: storedPreset.preset.id,
                name: name,
                outputFormat: outputFormat,
                resize: resize,
                options: options
            )
            try storage.update(storedPreset, with: preset)
            reload()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
