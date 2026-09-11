import SwiftUI

struct AddAudioPresetSheet: View {
    @ObservedObject var store: AudioPresetStore
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var outputFormatText: String
    let editingPreset: StoredAudioPreset?
    @State private var bitrateText = "192"
    @State private var sampleRateText = ""
    @State private var channelsText = ""
    @State private var moreArgumentsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editingPreset == nil ? "Add Audio Preset" : "Edit Audio Preset")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Name")
                    TextField("e.g. MP3 voice", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Convert to")
                    Picker("Convert to", selection: $outputFormatText) {
                        ForEach(VideoOutputFormat.audioPresetFormats) { format in
                            Text(format.label).tag(format.label)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()
            optionsView

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
        .padding(20)
        .frame(width: 380)
    }

    private var optionsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Options")
                .fontWeight(.medium)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                if outputFormat?.supportsAudioBitrate == true {
                    GridRow {
                        Text("Bitrate")
                        HStack(spacing: 6) {
                            TextField("192", text: $bitrateText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 86)
                            Text("kbps")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GridRow {
                    Text("Sample rate")
                    HStack(spacing: 6) {
                        TextField("Original", text: $sampleRateText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 86)
                        Text("Hz")
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow {
                    Text("Channels")
                    HStack(spacing: 6) {
                        TextField("Original", text: $channelsText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 86)
                        Text("1 mono, 2 stereo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow(alignment: .top) {
                    Text("More args")
                        .padding(.top, 4)
                    TextField("e.g. -af loudnorm", text: $moreArgumentsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    private func loadEditingPreset() {
        guard let preset = editingPreset?.preset else { return }
        name = preset.name
        outputFormatText = preset.outputFormat.label
        bitrateText = preset.options?.audioBitrateKbps.map(String.init) ?? "192"
        sampleRateText = preset.options?.audioSampleRateHz.map(String.init) ?? ""
        channelsText = preset.options?.audioChannels.map(String.init) ?? ""
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
        return (outputFormat.supportsAudioBitrate && bitrateValue == nil)
            || (sampleRateValue == nil && !sampleRateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || (channelsValue == nil && !channelsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var bitrateValue: Int? {
        let trimmed = bitrateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), (64...320).contains(value) else { return nil }
        return value
    }

    private var sampleRateValue: Int? {
        let trimmed = sampleRateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), (8_000...192_000).contains(value) else { return nil }
        return value
    }

    private var channelsValue: Int? {
        let trimmed = channelsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), (1...8).contains(value) else { return nil }
        return value
    }

    private var moreArguments: [String]? {
        // ponytail: whitespace-delimited FFmpeg options only; add quoted-value parsing when UI needs metadata with spaces.
        let arguments = moreArgumentsText.split(whereSeparator: \.isWhitespace).map(String.init)
        return arguments.isEmpty ? nil : arguments
    }

    private func options(for format: VideoOutputFormat) -> VideoEncodingOptions? {
        VideoEncodingOptions(
            quality: nil,
            fps: nil,
            removesAudio: nil,
            loopCount: nil,
            audioBitrateKbps: format.supportsAudioBitrate ? bitrateValue : nil,
            audioSampleRateHz: sampleRateValue,
            audioChannels: channelsValue,
            moreArguments: moreArguments
        )
    }
}
