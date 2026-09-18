import SwiftUI

struct AddVideoPresetSheet: View {
    @ObservedObject var store: VideoPresetStore
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var outputFormatText: String
    let editingPreset: StoredVideoPreset?
    @State private var qualityText = "70"
    @State private var fpsText = ""
    @State private var maxWidthText = ""
    @State private var audioEnabled = true
    @State private var loopText = "0"
    @State private var compressionLevelText = "6"
    @State private var lossless = false
    @State private var videoBitrateText = ""
    @State private var audioBitrateText = "192"
    @State private var moreArgumentsText = ""
    @State private var codec = VideoCodec.h264
    @State private var filterControls = VideoFilterControls()
    @State private var generatedMoreArgumentsText: String?

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
            applyAnimatedImageDefaultsIfNeeded()
        }
        .onChange(of: moreArgumentsText) { text in
            syncFilterControls(from: text)
        }
        .onChange(of: filterControls) { _ in
            syncMoreArgumentsFromFilterControls()
        }
        .padding(20)
        .frame(width: 460)
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

                    GridRow {
                        Text("Max width")
                        HStack(spacing: 6) {
                            TextField("Original", text: $maxWidthText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 86)
                            Text("px")
                                .foregroundStyle(.secondary)
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
                            TextEditor(text: $moreArgumentsText)
                                .font(.system(.body, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .padding(5)
                                .frame(height: 72)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color(nsColor: .separatorColor))
                                }
                                .accessibilityLabel("Extra FFmpeg arguments")
                            Text("Parsed as arguments and passed directly to FFmpeg without a shell")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !moreArgumentsText.isEmpty, parsedMoreArguments == nil {
                                Text("Invalid arguments: check quotes and -vf value")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    GridRow(alignment: .top) {
                        Color.clear.frame(width: 1, height: 1)
                        filterBuilder
                    }
                }
            }
        }
    }

    private var filterBuilder: some View {
        DisclosureGroup("Filter builder") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Color adjustments", isOn: $filterControls.adjustsColor)

                if filterControls.adjustsColor {
                    filterSlider("Gamma", value: $filterControls.gamma, range: 0.1...3, step: 0.05)
                    filterSlider("Brightness", value: $filterControls.brightness, range: -1...1, step: 0.01)
                    filterSlider("Saturation", value: $filterControls.saturation, range: 0...3, step: 0.05)
                }

                HStack {
                    Text("Pixel format")
                    Spacer()
                    Picker("Pixel format", selection: $filterControls.pixelFormat) {
                        Text("Unchanged").tag("")
                        Text("RGBA").tag("rgba")
                        Text("YUV 4:2:0").tag("yuv420p")
                        Text("YUV 4:4:4").tag("yuv444p")
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
            .padding(.top, 8)
        }
    }

    private func filterSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack {
            Text(label)
                .frame(width: 76, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(formattedFilterValue(value.wrappedValue))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func loadEditingPreset() {
        guard let preset = editingPreset?.preset else {
            syncCodecSelection()
            applyAnimatedImageDefaultsIfNeeded()
            return
        }
        name = preset.name
        outputFormatText = preset.outputFormat.label
        qualityText = preset.options?.quality.map(String.init) ?? defaultQualityText(for: preset.outputFormat)
        fpsText = preset.options?.fps.map { formatted($0) } ?? ""
        maxWidthText = preset.options?.maxWidth.map(String.init) ?? ""
        audioEnabled = !(preset.options?.removesAudio ?? false)
        loopText = preset.options?.loopCount.map(String.init) ?? "0"
        compressionLevelText = preset.options?.compressionLevel.map(String.init) ?? "6"
        lossless = preset.options?.lossless ?? false
        videoBitrateText = preset.options?.videoBitrateKbps.map(String.init) ?? ""
        audioBitrateText = preset.options?.audioBitrateKbps.map(String.init) ?? "192"
        moreArgumentsText = VideoFFmpegCommandBuilder.additionalArgumentsText(preset.options?.moreArguments ?? [])
        syncFilterControls(from: moreArgumentsText)
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
            || (maxWidthValue == nil && !maxWidthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || (outputFormat.supportsLoop && loopValue == nil)
            || (outputFormat.supportsCompressionLevel && compressionLevelValue == nil)
            || (outputFormat.supportsVideoBitrate && videoBitrateValue == nil && !videoBitrateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || (outputFormat.supportsAudioBitrate && bitrateValue == nil)
            || parsedMoreArguments == nil
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

    private var maxWidthValue: Int? {
        let trimmed = maxWidthText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), (1...16_384).contains(value) else { return nil }
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
            codec: format.supportedCodecs.contains(codec) ? codec : nil,
            maxWidth: maxWidthValue
        )
        return format.hasEncodingOptions ? options : nil
    }

    private var moreArguments: [String]? {
        let arguments = parsedMoreArguments ?? []
        return arguments.isEmpty ? nil : arguments
    }

    private var parsedMoreArguments: [String]? {
        try? VideoFFmpegCommandBuilder.additionalArguments(moreArgumentsText)
    }

    private func syncFilterControls(from text: String) {
        if text == generatedMoreArgumentsText {
            generatedMoreArgumentsText = nil
            return
        }
        guard let arguments = try? VideoFFmpegCommandBuilder.additionalArguments(text) else { return }
        filterControls = VideoFilterControls(filter: VideoFFmpegCommandBuilder.videoFilter(in: arguments))
    }

    private func syncMoreArgumentsFromFilterControls() {
        guard let arguments = try? VideoFFmpegCommandBuilder.additionalArguments(moreArgumentsText) else { return }
        let currentFilter = VideoFFmpegCommandBuilder.videoFilter(in: arguments)
        let updatedFilter = filterControls.applying(to: currentFilter)
        let updatedArguments = VideoFFmpegCommandBuilder.replacingVideoFilter(in: arguments, with: updatedFilter)
        let updatedText = VideoFFmpegCommandBuilder.additionalArgumentsText(updatedArguments)
        guard updatedText != moreArgumentsText else { return }
        generatedMoreArgumentsText = updatedText
        moreArgumentsText = updatedText
    }

    private func applyAnimatedImageDefaultsIfNeeded() {
        guard editingPreset == nil, let outputFormat, [.gif, .webp].contains(outputFormat) else { return }
        maxWidthText = "375"
        if fpsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fpsText = "12"
        }
        guard outputFormat == .webp else { return }
        qualityText = "90"
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

    private func formattedFilterValue(_ value: Double) -> String {
        String(format: "%.2f", value)
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
