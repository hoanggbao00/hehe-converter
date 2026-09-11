import SwiftUI

struct AddVideoPresetSheet: View {
    @ObservedObject var store: VideoPresetStore
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var outputFormatText: String
    let editingPreset: StoredVideoPreset?
    @State private var qualityText = "70"
    @State private var fpsText = ""
    @State private var removesAudio = false
    @State private var loopText = "0"
    @State private var audioBitrateText = "192"
    @State private var moreArgumentsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editingPreset == nil ? "Add Video Preset" : "Edit Video Preset")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Name")
                    TextField("e.g. MP4 for web", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Convert to")
                    AutocompleteComboBox(
                        text: $outputFormatText,
                        values: VideoOutputFormat.suggestedFormats.map(\.label)
                    )
                    .frame(maxWidth: .infinity)
                }
            }

            if outputFormat?.hasEncodingOptions == true {
                Divider()
                optionsView
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                Button(editingPreset == nil ? "Add" : "Save") {
                    guard let outputFormat else { return }
                    if let editingPreset {
                        store.update(editingPreset, name: trimmedName, outputFormat: outputFormat, options: options(for: outputFormat))
                    } else {
                        store.add(name: trimmedName, outputFormat: outputFormat, options: options(for: outputFormat))
                    }
                    isPresented = false
                }
                .disabled(trimmedName.isEmpty || outputFormat == nil || optionsInvalid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: loadEditingPreset)
        .onChange(of: outputFormatText) { _ in
            fillDefaultMoreArgumentsIfNeeded()
        }
        .padding(20)
        .frame(width: 380)
    }

    @ViewBuilder
    private var optionsView: some View {
        if let outputFormat {
            VStack(alignment: .leading, spacing: 10) {
                Text("Options")
                    .fontWeight(.medium)

                if outputFormat.supportsQuality {
                    HStack {
                        Text("Quality")
                        TextField("70", text: $qualityText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 86)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }

                if outputFormat.supportsFPS {
                    HStack {
                        Text("FPS")
                        TextField("Original", text: $fpsText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 86)
                        Text("empty = original")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if outputFormat.supportsAudioToggle {
                    Toggle("Remove audio", isOn: $removesAudio)
                }

                if outputFormat.supportsLoop {
                    HStack {
                        Text("Loop")
                        TextField("0", text: $loopText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 86)
                        Text("0 = infinite")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if outputFormat.supportsAudioBitrate {
                    HStack {
                        Text("Bitrate")
                        TextField("192", text: $audioBitrateText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 86)
                        Text("kbps")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("More args")
                    TextField("e.g. -preset picture", text: $moreArgumentsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    private func loadEditingPreset() {
        guard let preset = editingPreset?.preset else {
            fillDefaultMoreArgumentsIfNeeded()
            return
        }
        name = preset.name
        outputFormatText = preset.outputFormat.label
        qualityText = preset.options?.quality.map(String.init) ?? "70"
        fpsText = preset.options?.fps.map { formatted($0) } ?? ""
        removesAudio = preset.options?.removesAudio ?? false
        loopText = preset.options?.loopCount.map(String.init) ?? "0"
        audioBitrateText = preset.options?.audioBitrateKbps.map(String.init) ?? "192"
        moreArgumentsText = preset.options?.moreArguments?.joined(separator: " ") ?? ""
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var outputFormat: VideoOutputFormat? {
        VideoOutputFormat.format(matching: outputFormatText)
    }

    private var optionsInvalid: Bool {
        guard let outputFormat else { return false }
        return (outputFormat.supportsQuality && qualityValue == nil)
            || (outputFormat.supportsFPS && fpsValue == nil && !fpsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || (outputFormat.supportsLoop && loopValue == nil)
            || (outputFormat.supportsAudioBitrate && bitrateValue == nil)
    }

    private var qualityValue: Int? {
        let trimmed = qualityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), (1...100).contains(value) else { return nil }
        return value
    }

    private var fpsValue: Double? {
        let trimmed = fpsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed), value > 0 else { return nil }
        return value
    }

    private var loopValue: Int? {
        let trimmed = loopText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value >= 0 else { return nil }
        return value
    }

    private var bitrateValue: Int? {
        let trimmed = audioBitrateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private func options(for format: VideoOutputFormat) -> VideoEncodingOptions? {
        let options = VideoEncodingOptions(
            quality: format.supportsQuality ? qualityValue : nil,
            fps: format.supportsFPS ? fpsValue : nil,
            removesAudio: format.supportsAudioToggle ? removesAudio : nil,
            loopCount: format.supportsLoop ? (loopValue ?? 0) : nil,
            audioBitrateKbps: format.supportsAudioBitrate ? bitrateValue : nil,
            moreArguments: moreArguments
        )
        return format.hasEncodingOptions ? options : nil
    }

    private var moreArguments: [String]? {
        // ponytail: whitespace-delimited FFmpeg options only; add quoted-value parsing when UI needs metadata with spaces.
        let arguments = moreArgumentsText.split(whereSeparator: \.isWhitespace).map(String.init)
        return arguments.isEmpty ? nil : arguments
    }

    private func fillDefaultMoreArgumentsIfNeeded() {
        guard editingPreset == nil,
              outputFormat == .webp,
              moreArgumentsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        moreArgumentsText = "-cr_size 0"
    }

    private func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}
