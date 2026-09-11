import SwiftUI

struct ConversionSettingsSection: View {
    enum MediaKind: String, CaseIterable, Identifiable {
        case image = "Image"
        case video = "Video"
        case audio = "Audio"

        var id: Self { self }
    }

    @ObservedObject var imagePresetStore: ImagePresetStore
    @ObservedObject var videoPresetStore: VideoPresetStore
    @Binding var showsImagePresetSheet: Bool
    @Binding var imagePresetName: String
    @Binding var imageOutputFormatText: String
    @Binding var editingImagePreset: StoredImagePreset?
    @State private var selectedMediaKind = MediaKind.image

    var body: some View {
        Section("Conversion") {
            Picker("Media type", selection: $selectedMediaKind) {
                ForEach(MediaKind.allCases) { kind in
                    Text(label(for: kind)).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedMediaKind {
        case .image:
            ImagePresetList(
                store: imagePresetStore,
                showsPresetSheet: $showsImagePresetSheet,
                presetName: $imagePresetName,
                outputFormatText: $imageOutputFormatText,
                editingPreset: $editingImagePreset
            )
        case .video:
            VideoPresetList(store: videoPresetStore)
        case .audio:
            Text("No \(selectedMediaKind.rawValue.lowercased()) presets")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 72)
        }
    }

    private func label(for kind: MediaKind) -> String {
        switch kind {
        case .image:
            "Image (\(imagePresetStore.presets.count))"
        case .video:
            "Video (\(videoPresetStore.presets.count))"
        case .audio:
            kind.rawValue
        }
    }
}
