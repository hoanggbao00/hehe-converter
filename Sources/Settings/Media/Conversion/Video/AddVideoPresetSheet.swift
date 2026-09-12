import SwiftUI

struct AddVideoPresetSheet: View {
    @ObservedObject var store: VideoPresetStore
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var outputFormatText: String
    let editingPreset: StoredVideoPreset?
    @State private var qualityText = "70"
    @State private var fpsText = ""
    @State private var audioEnabled = true
    @State private var loopText = "0"
    @State private var compressionLevelText = "6"
    @State private var lossless = false
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
            syncCodecSelection()
            applyWebPDefaultsIfNeeded()
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

                    if outputFormat.supportsLossless {
                        GridRow {
                            Text("Lossless")
                            Toggle("Lossless", isOn: $lossless)
                                .labelsHidden()
                        }
                    }

                    if outputFormat.supportsQuality, !lossless {
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
                            Text("Audio")
                            Toggle("Audio", isOn: $audioEnabled)
                                .labelsHidden()
                        }
                    }

                    if outputFormat.supportsVideoBitrate {
                        GridRow {
                            Text("Bitrate")
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

                    if outputFormat.supportsCompressionLevel {
                        GridRow {
                            Text("Compression")
                            HStack(spacing: 6) {
                                TextField("6", text: $compressionLevelText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 86)
                                Text("0–6")
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
                            Text("Extra FFmpeg options appended after built-in encoding args")
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
            syncCodecSelection()
            applyWebPDefaultsIfNeeded()
            return
        }
        name = preset.name
        outputFormatText = preset.outputFormat.label
        qualityText = preset.options?.quality.map(String.init) ?? defaultQualityText(for: preset.outputFormat)
        fpsText = preset.options?.fps.map { formatted($0) } ?? ""
        audioEnabled = !(preset.options?.removesAudio ?? false)
        loopText = preset.options?.loopCount.map(String.init) ?? "0"
        compressionLevelText = preset.options?.compressionLevel.map(String.init) ?? "6"
        lossless = preset.options?.lossless ?? false
        videoBitrateText = preset.options?.videoBitrateKbps.map(String.init) ?? ""
        audioBitrateText = preset.options?.audioBitrateKbps.map(String.init) ?? "192"
        moreArgumentsText = preset.options?.moreArguments?.joined(separator: " ") ?? ""
        codec = preset.options?.codec
            ?? preset.outputFormat.supportedCodecs.first
            ?? .h264
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var outputFormat: VideoOutputFormat? {
        VideoOutputFormat.format(matching: outputFormatText)
    }

    private var optionsInvalid: Bool {
        guard let outputFormat else { return false }
        return (outputFormat.supportsQuality && !lossless && qualityValue == nil)
            || (outputFormat.supportsFPS && fpsValue == nil && !fpsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || (outputFormat.supportsLoop && loopValue == nil)
            || (outputFormat.supportsCompressionLevel && compressionLevelValue == nil)
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

    private var compressionLevelValue: Int? {
        let trimmed = compressionLevelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), (0...6).contains(value) else { return nil }
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
            quality: format.supportsQuality && !lossless ? qualityValue : nil,
            fps: format.supportsFPS ? fpsValue : nil,
            removesAudio: format.supportsAudioToggle ? !audioEnabled : nil,
            loopCount: format.supportsLoop ? (loopValue ?? 0) : nil,
            videoBitrateKbps: format.supportsVideoBitrate ? videoBitrateValue : nil,
            audioBitrateKbps: format.supportsAudioBitrate ? bitrateValue : nil,
            compressionLevel: format.supportsCompressionLevel ? compressionLevelValue : nil,
            lossless: format.supportsLossless ? lossless : nil,
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

    private func applyWebPDefaultsIfNeeded() {
        guard editingPreset == nil, outputFormat == .webp else { return }
        qualityText = "90"
        if fpsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fpsText = "24"
        }
        if compressionLevelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            compressionLevelText = "6"
        }
        if moreArgumentsText.trimmingCharacters(in: .whitespacesAndNewlines) == "-cr_size 0" {
            moreArgumentsText = ""
        }
    }

    private func syncCodecSelection() {
        guard let format = outputFormat else { return }
        guard !format.supportedCodecs.isEmpty else { return }
        if !format.supportedCodecs.contains(codec) {
            codec = format.supportedCodecs[0]
        }
    }

    private func defaultQualityText(for format: VideoOutputFormat) -> String {
        format == .webp ? "90" : "70"
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
