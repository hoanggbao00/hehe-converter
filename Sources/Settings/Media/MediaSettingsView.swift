import SwiftUI

struct MediaSettingsView: View {
    @StateObject private var ffmpeg = FFmpegInstallStore()
    @StateObject private var imagePresetStore = ImagePresetStore()
    @State private var confirmsDelete = false
    @State private var showsImagePresetSheet = false
    @State private var imagePresetName = ""
    @State private var imageOutputFormatText = ImageOutputFormat.webp.label
    @State private var editingImagePreset: StoredImagePreset?

    var body: some View {
        Form {
            FFmpegConfigSection(ffmpeg: ffmpeg, confirmsDelete: $confirmsDelete)
            ConversionSettingsSection(
                imagePresetStore: imagePresetStore,
                showsImagePresetSheet: $showsImagePresetSheet,
                imagePresetName: $imagePresetName,
                imageOutputFormatText: $imageOutputFormatText,
                editingImagePreset: $editingImagePreset
            )
        }
        .formStyle(.grouped)
        .background(OverlayScrollerConfigurator())
        .sheet(isPresented: $showsImagePresetSheet, onDismiss: { editingImagePreset = nil }) {
            AddImagePresetSheet(
                store: imagePresetStore,
                isPresented: $showsImagePresetSheet,
                name: $imagePresetName,
                outputFormatText: $imageOutputFormatText,
                editingPreset: editingImagePreset
            )
        }
        .task {
            ffmpeg.refreshAndVerifyIfNeeded()
        }
        .confirmationDialog(
            "Delete ffmpeg & ffprobe?",
            isPresented: $confirmsDelete
        ) {
            Button("Delete", role: .destructive) {
                ffmpeg.deleteInstalledFiles()
            }
        } message: {
            Text("You can re-download them anytime in Media settings.")
        }
    }
}
