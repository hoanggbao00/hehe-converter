import SwiftUI

struct AddImagePresetSheet: View {
    @ObservedObject var store: ImagePresetStore
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var outputFormatText: String
    let editingPreset: StoredImagePreset?
    @State private var resizesImage = false
    @State private var resizeMode = ImageResizeMode.fitWithin
    @State private var widthText = "1920"
    @State private var widthUnit = ImageDimensionUnit.pixels
    @State private var heightText = "1080"
    @State private var heightUnit = ImageDimensionUnit.pixels
    @State private var percentageText = "50"
    @State private var linkedAspectRatio = 16.0 / 9.0
    @State private var linkedAspectRatioLabel = "(16:9)"
    @State private var isSyncingDimensions = false
    @State private var quality = 80.0
    @State private var lossless = false
    @State private var pngPrediction = ImagePNGPrediction.paeth
    @State private var tiffCompression = ImageTIFFCompression.packbits
    @State private var usesRLE = true
    @State private var usesGlobalPalette = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editingPreset == nil ? "Add Image Preset" : "Edit Image Preset")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Name")
                    TextField("e.g. WebP for web", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Convert to")
                    AutocompleteComboBox(
                        text: $outputFormatText,
                        values: ImageOutputFormat.availableFormats.map(\.label)
                    )
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Resize", isOn: $resizesImage)

                if resizesImage {
                    Picker("", selection: usesPercentage) {
                        Text("Size").tag(false)
                        Text("Percent").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    resizeOptions
                }
            }

            if selectedOutputFormat?.hasEncodingOptions == true {
                Divider()
                encodingOptions
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                Button(editingPreset == nil ? "Add" : "Save") {
                    guard let format = selectedOutputFormat else { return }
                    if let editingPreset {
                        store.update(
                            editingPreset,
                            name: trimmedName,
                            outputFormat: format,
                            resize: resize,
                            options: encodingOptions(for: format)
                        )
                    } else {
                        store.add(
                            name: trimmedName,
                            outputFormat: format,
                            resize: resize,
                            options: encodingOptions(for: format)
                        )
                    }
                    isPresented = false
                }
                .disabled(trimmedName.isEmpty || selectedOutputFormat == nil || resizeIsInvalid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: loadEditingPreset)
        .padding(20)
        .frame(width: 380)
    }

    private func loadEditingPreset() {
        guard let preset = editingPreset?.preset else { return }
        name = preset.name
        outputFormatText = preset.outputFormat.label
        resizesImage = preset.resize != nil
        if let resize = preset.resize {
            resizeMode = resize.mode
            widthText = resize.width.map { formatted($0.value, unit: $0.unit) } ?? widthText
            widthUnit = resize.width?.unit ?? widthUnit
            heightText = resize.height.map { formatted($0.value, unit: $0.unit) } ?? heightText
            heightUnit = resize.height?.unit ?? heightUnit
            percentageText = resize.percentage.map { formatted($0, unit: .percent) } ?? percentageText
        }
        quality = Double(preset.options?.quality ?? 80)
        lossless = preset.options?.lossless ?? false
        pngPrediction = preset.options?.pngPrediction ?? .paeth
        tiffCompression = preset.options?.tiffCompression ?? .packbits
        usesRLE = preset.options?.rle ?? true
        usesGlobalPalette = preset.options?.globalPalette ?? true
    }

    @ViewBuilder
    private var encodingOptions: some View {
        if let format = selectedOutputFormat {
            VStack(alignment: .leading, spacing: 10) {
                Text("Options")
                    .fontWeight(.medium)

                if format.supportsLossless {
                    Toggle("Lossless", isOn: $lossless)
                }

                if format.supportsQuality, !lossless {
                    HStack {
                        Text("Quality")
                        Slider(value: $quality, in: 1...100, step: 1)
                        Text("\(Int(quality))")
                            .monospacedDigit()
                            .frame(width: 26, alignment: .trailing)
                    }
                }

                if format.supportsPNGPrediction {
                    Picker("Prediction", selection: $pngPrediction) {
                        ForEach(ImagePNGPrediction.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                }

                if format.supportsTIFFCompression {
                    Picker("Compression", selection: $tiffCompression) {
                        ForEach(ImageTIFFCompression.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                }

                if format.supportsRLE {
                    Toggle("RLE compression", isOn: $usesRLE)
                }

                if format.supportsGlobalPalette {
                    Toggle("Global palette", isOn: $usesGlobalPalette)
                }
            }
        }
    }

    @ViewBuilder
    private var resizeOptions: some View {
        switch resizeMode {
        case .fitWithin, .exactSize:
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width")
                    dimensionField(text: $widthText, unit: $widthUnit) {
                        syncHeightFromWidth()
                    }
                }

                aspectButton
                    .padding(.bottom, 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Height")
                    dimensionField(text: $heightText, unit: $heightUnit) {
                        syncWidthFromHeight()
                    }
                }

                Text(aspectRatioLabel)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
                    .padding(.bottom, 6)
            }
        case .percentage:
            HStack {
                Text("Scale")
                TextField("50", text: $percentageText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                Text("%")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dimensionField(
        text: Binding<String>,
        unit: Binding<ImageDimensionUnit>,
        onChange: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            ScrubbableTextField(
                text: text,
                step: unit.wrappedValue == .pixels ? 1 : 0.1,
                usesIntegerValues: unit.wrappedValue == .pixels,
                onChange: onChange
            )
                .frame(width: 72)
            Picker("", selection: unit) {
                ForEach(ImageDimensionUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .labelsHidden()
            .frame(width: 50)
            .onChange(of: unit.wrappedValue) { _ in onChange() }
        }
    }

    private var aspectButton: some View {
        Button {
            resizeMode = keepAspectRatio ? .exactSize : .fitWithin
            if keepAspectRatio,
               let width = Double(widthText),
               let height = Double(heightText),
               height > 0 {
                linkedAspectRatio = width / height
                linkedAspectRatioLabel = Self.aspectRatioLabel(width: width, height: height)
                heightUnit = widthUnit
            }
        } label: {
            Image(systemName: "link")
                .foregroundStyle(keepAspectRatio ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(keepAspectRatio ? "Keep aspect ratio" : "Free size")
    }

    private var keepAspectRatio: Bool {
        resizeMode != .exactSize
    }

    private var aspectRatioLabel: String {
        guard widthUnit == heightUnit,
              let width = Double(widthText),
              let height = Double(heightText),
              width > 0, height > 0 else { return "" }

        guard !keepAspectRatio else { return linkedAspectRatioLabel }
        return Self.aspectRatioLabel(width: width, height: height)
    }

    static func aspectRatioLabel(width: Double, height: Double) -> String {
        let ratio = width / height
        var bestNumerator: Int?
        var bestDenominator = 1
        var bestComplexity = Int.max

        for denominator in 1...32 {
            let numerator = max(1, Int((ratio * Double(denominator)).rounded()))
            let heightError = abs(height - width * Double(denominator) / Double(numerator))
            let complexity = numerator + denominator
            if heightError <= 0.5, complexity < bestComplexity {
                bestNumerator = numerator
                bestDenominator = denominator
                bestComplexity = complexity
            }
        }

        if let bestNumerator {
            let divisor = greatestCommonDivisor(bestNumerator, bestDenominator)
            return "(\(bestNumerator / divisor):\(bestDenominator / divisor))"
        }

        let scaledWidth = Int((width * 100).rounded())
        let scaledHeight = Int((height * 100).rounded())
        let divisor = greatestCommonDivisor(scaledWidth, scaledHeight)
        return "(\(scaledWidth / divisor):\(scaledHeight / divisor))"
    }

    private var usesPercentage: Binding<Bool> {
        Binding(
            get: { resizeMode == .percentage },
            set: { resizeMode = $0 ? .percentage : .fitWithin }
        )
    }

    private var selectedOutputFormat: ImageOutputFormat? {
        ImageOutputFormat.availableFormat(matching: outputFormatText)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resize: ImageResize? {
        guard resizesImage else { return nil }

        switch resizeMode {
        case .fitWithin, .exactSize:
            return ImageResize(
                mode: resizeMode,
                width: dimension(value: widthText, unit: widthUnit),
                height: dimension(value: heightText, unit: heightUnit),
                percentage: nil,
                keepAspectRatio: keepAspectRatio
            )
        case .percentage:
            return ImageResize(
                mode: .percentage,
                width: nil,
                height: nil,
                percentage: Double(percentageText),
                keepAspectRatio: true
            )
        }
    }

    private func encodingOptions(for format: ImageOutputFormat) -> ImageEncodingOptions? {
        guard format.hasEncodingOptions else { return nil }
        return ImageEncodingOptions(
            quality: format.supportsQuality && !lossless ? Int(quality) : nil,
            lossless: format.supportsLossless ? lossless : nil,
            pngPrediction: format.supportsPNGPrediction ? pngPrediction : nil,
            tiffCompression: format.supportsTIFFCompression ? tiffCompression : nil,
            rle: format.supportsRLE ? usesRLE : nil,
            globalPalette: format.supportsGlobalPalette ? usesGlobalPalette : nil
        )
    }

    private var resizeIsInvalid: Bool {
        guard resizesImage else { return false }

        switch resizeMode {
        case .fitWithin, .exactSize:
            return dimension(value: widthText, unit: widthUnit) == nil
                || dimension(value: heightText, unit: heightUnit) == nil
        case .percentage:
            guard let value = Double(percentageText) else { return true }
            return value <= 0
        }
    }

    private func dimension(value: String, unit: ImageDimensionUnit) -> ImageDimension? {
        guard let number = Double(value), number > 0 else { return nil }
        return ImageDimension(value: number, unit: unit)
    }

    private func syncHeightFromWidth() {
        guard keepAspectRatio, !isSyncingDimensions,
              let width = Double(widthText), linkedAspectRatio > 0 else { return }
        isSyncingDimensions = true
        heightUnit = widthUnit
        heightText = formatted(width / linkedAspectRatio, unit: heightUnit)
        isSyncingDimensions = false
    }

    private func syncWidthFromHeight() {
        guard keepAspectRatio, !isSyncingDimensions,
              let height = Double(heightText), linkedAspectRatio > 0 else { return }
        isSyncingDimensions = true
        widthUnit = heightUnit
        widthText = formatted(height * linkedAspectRatio, unit: widthUnit)
        isSyncingDimensions = false
    }

    private func formatted(_ value: Double, unit: ImageDimensionUnit) -> String {
        guard unit != .pixels else { return String(Int(value.rounded())) }
        return value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var lhs = lhs
        var rhs = rhs
        while rhs != 0 {
            (lhs, rhs) = (rhs, lhs % rhs)
        }
        return max(lhs, 1)
    }
}
