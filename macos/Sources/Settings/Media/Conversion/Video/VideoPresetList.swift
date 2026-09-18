import SwiftUI

struct VideoPresetList: View {
    @ObservedObject var store: VideoPresetStore
    @State private var presetToDelete: StoredVideoPreset?
    @State private var editingPreset: StoredVideoPreset?
    @State private var showsPresetSheet = false
    @State private var showsCommandSheet = false
    @State private var presetName = ""
    @State private var outputFormatText = VideoOutputFormat.mp4.label
    @State private var commandText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Button(action: store.reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")

                Button(action: store.openVideoPresetFolder) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Open Folder")

                Button("Add Preset", action: showAddPreset)
                Button("Add Command", action: showAddCommand)
            }

            if store.presets.isEmpty {
                Text("No video presets")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                VStack(spacing: 2) {
                    ForEach(store.presets) { storedPreset in
                        VideoPresetRow(
                            preset: storedPreset.preset,
                            onEdit: { edit(storedPreset) },
                            onDelete: { presetToDelete = storedPreset }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showsPresetSheet, onDismiss: { editingPreset = nil }) {
            AddVideoPresetSheet(
                store: store,
                isPresented: $showsPresetSheet,
                name: $presetName,
                outputFormatText: $outputFormatText,
                editingPreset: editingPreset
            )
        }
        .sheet(isPresented: $showsCommandSheet, onDismiss: { editingPreset = nil }) {
            AddVideoCommandSheet(
                store: store,
                isPresented: $showsCommandSheet,
                name: $presetName,
                command: $commandText,
                editingPreset: editingPreset
            )
        }
        .confirmationDialog(
            presetToDelete.map { "Delete “\($0.preset.name)” preset?" } ?? "Delete preset?",
            isPresented: Binding(
                get: { presetToDelete != nil },
                set: { if !$0 { presetToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let presetToDelete else { return }
                store.delete(presetToDelete)
                self.presetToDelete = nil
            }
        } message: {
            Text("This removes the preset JSON file.")
        }
    }

    private func showAddPreset() {
        editingPreset = nil
        presetName = ""
        outputFormatText = VideoOutputFormat.mp4.label
        showsPresetSheet = true
    }

    private func showAddCommand() {
        editingPreset = nil
        presetName = ""
        commandText = ""
        showsCommandSheet = true
    }

    private func edit(_ storedPreset: StoredVideoPreset) {
        editingPreset = storedPreset
        presetName = storedPreset.preset.name
        outputFormatText = storedPreset.preset.outputFormat.label
        commandText = storedPreset.preset.ffmpegCommand
        if storedPreset.preset.presetType == .command {
            showsCommandSheet = true
        } else {
            showsPresetSheet = true
        }
    }
}

private struct VideoPresetRow: View {
    let preset: VideoPreset
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(preset.name)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("(\(preset.outputFormat.label))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isHovered ? Color.primary.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
