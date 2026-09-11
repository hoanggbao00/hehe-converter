import SwiftUI

struct ImagePresetList: View {
    @ObservedObject var store: ImagePresetStore
    @Binding var showsPresetSheet: Bool
    @Binding var presetName: String
    @Binding var outputFormatText: String
    @Binding var editingPreset: StoredImagePreset?
    @State private var presetToDelete: StoredImagePreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Button(action: store.reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")

                Button(action: store.openImagePresetFolder) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Open Folder")

                Button("Add Preset", action: showAddPreset)
            }

            if store.presets.isEmpty {
                Text("No image presets")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                VStack(spacing: 2) {
                    ForEach(store.presets) { storedPreset in
                        ImagePresetRow(
                            storedPreset: storedPreset,
                            onEdit: { edit(storedPreset) },
                            onDelete: { presetToDelete = storedPreset }
                        )
                    }
                }
            }
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
        outputFormatText = ImageOutputFormat.webp.label
        showsPresetSheet = true
    }

    private func edit(_ preset: StoredImagePreset) {
        editingPreset = preset
        presetName = preset.preset.name
        outputFormatText = preset.preset.outputFormat.label
        showsPresetSheet = true
    }
}

private struct ImagePresetRow: View {
    let storedPreset: StoredImagePreset
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    private var preset: ImagePreset { storedPreset.preset }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(preset.name)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("(\(preset.outputFormat.label))")
                        .foregroundStyle(.secondary)
                }

                ForEach(details, id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    private var details: [String] {
        [resizeDetail, qualityDetail].compactMap { $0 }
    }

    private var resizeDetail: String? {
        guard let resize = preset.resize else { return nil }
        switch resize.mode {
        case .fitWithin, .exactSize:
            guard let width = resize.width, let height = resize.height else { return nil }
            let mode = resize.mode == .fitWithin ? "Fit within" : "Exact size"
            return "\(mode): \(dimension(width)) x \(dimension(height))"
        case .percentage:
            guard let percentage = resize.percentage else { return nil }
            return "Resize: \(value(percentage))%"
        }
    }

    private var qualityDetail: String? {
        guard let options = preset.options else { return nil }
        if options.lossless == true { return "Quality: lossless" }
        if let quality = options.quality { return "Quality: \(quality)" }
        if let prediction = options.pngPrediction { return "Prediction: \(prediction.label)" }
        if let compression = options.tiffCompression { return "Compression: \(compression.label)" }
        if let rle = options.rle { return "RLE: \(rle ? "on" : "off")" }
        if let globalPalette = options.globalPalette { return "Global palette: \(globalPalette ? "on" : "off")" }
        return nil
    }

    private func dimension(_ dimension: ImageDimension) -> String {
        "\(value(dimension.value))\(dimension.unit.rawValue)"
    }

    private func value(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}
