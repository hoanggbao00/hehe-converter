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
    @State private var videoBitrateText = ""
    @State private var audioBitrateText = "192"
    @State private var moreArgumentsText = ""
    @State private var codec = VideoCodec.h264

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
                    Picker("Convert to", selection: $outputFormatText) {
                        ForEach(VideoOutputFormat.videoPresetFormats) { format in
                            Text(format.label).tag(format.label)
                        }
                    }
                    .labelsHidden()
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

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                    if !outputFormat.supportedCodecs.isEmpty {
                        GridRow {
                            Text("Codec")
                            Picker("Codec", selection: $codec) {
                                ForEach(outputFormat.supportedCodecs) { codec in
                                    Text(codec.label).tag(codec)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                    }

                    if outputFormat.supportsQuality {
                        GridRow {
                            Text("Quality")
                            HStack(spacing: 6) {
                                TextField("70", text: $qualityText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 86)
                                Text("%")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if outputFormat.supportsFPS {
                        GridRow {
                            Text("FPS")
                            HStack(spacing: 6) {
                                TextField("Original", text: $fpsText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 86)
                                Text("empty = original")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if outputFormat.supportsAudioToggle {
                        GridRow {
                            Text("Remove audio")
                            Toggle("Remove audio", isOn: $removesAudio)
                                .labelsHidden()
                        }
                    }

                    if outputFormat.supportsVideoBitrate {
                        GridRow {
                            Text("Video bitrate")
                            HStack(spacing: 6) {
                                TextField("Original", text: $videoBitrateText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 86)
                                Text("kbps")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if outputFormat.supportsLoop {
                        GridRow {
                            Text("Loop")
                            HStack(spacing: 6) {
                                TextField("0", text: $loopText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 86)
                                Text("0 = infinite")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if outputFormat.supportsAudioBitrate {
                        GridRow {
                            Text("Bitrate")
                            HStack(spacing: 6) {
                                TextField("192", text: $audioBitrateText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 86)
                                Text("kbps")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    GridRow(alignment: .top) {
                        Text("More args")
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 3) {
                            TextField("e.g. -preset picture", text: $moreArgumentsText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Text("e.g. -cr_size 0 -preset picture")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
        videoBitrateText = preset.options?.videoBitrateKbps.map(String.init) ?? ""
        audioBitrateText = preset.options?.audioBitrateKbps.map(String.init) ?? "192"
        moreArgumentsText = preset.options?.moreArguments?.joined(separator: " ") ?? ""
        codec = preset.options?.codec ?? .h264
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
            || (outputFormat.supportsVideoBitrate && videoBitrateValue == nil && !videoBitrateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private var videoBitrateValue: Int? {
        let trimmed = videoBitrateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), value > 0 else { return nil }
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
            videoBitrateKbps: format.supportsVideoBitrate ? videoBitrateValue : nil,
            audioBitrateKbps: format.supportsAudioBitrate ? bitrateValue : nil,
            moreArguments: moreArguments,
            codec: format.supportedCodecs.contains(codec) ? codec : nil
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

struct AddVideoCommandSheet: View {
    @ObservedObject var store: VideoPresetStore
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var command: String
    let editingPreset: StoredVideoPreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editingPreset == nil ? "Add Video Command" : "Edit Video Command")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Name")
                    TextField("e.g. WebM custom", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow(alignment: .top) {
                    Text("Command")
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: $command)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .frame(minHeight: 140, maxHeight: 220)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color(nsColor: .separatorColor))
                            }
                            .accessibilityLabel("FFmpeg command")
                        Text("Supports multiline commands with \\ continuations. App replaces input after -i and final output path with {input}/{output}.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                Button(editingPreset == nil ? "Add" : "Save") {
                    if let editingPreset {
                        store.updateCommand(editingPreset, name: trimmedName, command: command)
                    } else {
                        store.addCommand(name: trimmedName, command: command)
                    }
                    if store.errorMessage == nil {
                        isPresented = false
                    }
                }
                .disabled(trimmedName.isEmpty || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: loadEditingPreset)
        .padding(20)
        .frame(width: 520)
    }

    private func loadEditingPreset() {
        guard let preset = editingPreset?.preset else { return }
        name = preset.name
        command = preset.ffmpegCommand
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
