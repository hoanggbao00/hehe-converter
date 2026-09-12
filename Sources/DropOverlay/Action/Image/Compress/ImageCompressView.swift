import AppKit
import SwiftUI

struct ImageCompressView: View {
    static let singleWidth: CGFloat = 392
    static let multiColumnWidth: CGFloat = 340
    static let panelHeight: CGFloat = 404
    static let headerHeight: CGFloat = 48
    static let contentHeight = panelHeight - headerHeight

    let models: [ImageCompressModel]
    let sharedModel: ImageCompressModel
    let close: () -> Void
    let apply: (ImageCompressModel) async -> ImageCompressResult?
    let applyAll: (ImageCompressModel, [ImageCompressModel]) async -> [ImageCompressResult]?
    let reveal: ([URL]) -> Void
    let resizeWindow: (CGFloat, TimeInterval) -> Void

    @State private var applyScope: ResizeApplyScope
    @State private var completedModelIDs: Set<ImageCompressModel.ID> = []
    @State private var activeReflows = 0

    init(
        models: [ImageCompressModel],
        sharedModel: ImageCompressModel,
        close: @escaping () -> Void,
        apply: @escaping (ImageCompressModel) async -> ImageCompressResult?,
        applyAll: @escaping (ImageCompressModel, [ImageCompressModel]) async -> [ImageCompressResult]?,
        reveal: @escaping ([URL]) -> Void,
        resizeWindow: @escaping (CGFloat, TimeInterval) -> Void
    ) {
        self.models = models
        self.sharedModel = sharedModel
        self.close = close
        self.apply = apply
        self.applyAll = applyAll
        self.reveal = reveal
        self.resizeWindow = resizeWindow
        _applyScope = State(initialValue: models.count > 1 ? .all : .each)
    }

    private var columnWidth: CGFloat {
        models.count == 1 ? Self.singleWidth : Self.multiColumnWidth
    }

    var body: some View {
        OverlayPanelView(title: "Compress Image", close: close, actions: []) {
            VStack(spacing: 0) {
                if models.count > 1 {
                    HStack {
                        Text("Apply to")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Picker("Apply to", selection: Binding(
                            get: { applyScope },
                            set: { setApplyScope($0) }
                        )) {
                            ForEach(ResizeApplyScope.allCases) { scope in
                                Text(scope.rawValue).tag(scope)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 132)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 34)
                    Divider().opacity(0.36)
                }

                if applyScope == .all, models.count > 1 {
                    ImageCompressColumn(
                        model: sharedModel,
                        width: Self.singleWidth,
                        detailText: "Applies to \(models.count) images",
                        successFallbackText: "\(models.count) images compressed",
                        collapsesAfterCompletion: false
                    ) {
                        await applyAll(sharedModel, models)
                    } onComplete: { results in
                        close()
                        reveal(results.map(\.outputURL))
                    }
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 1) {
                            ForEach(models) { model in
                                ImageCompressColumn(
                                    model: model,
                                    width: columnWidth,
                                    detailText: models.count > 1 ? model.inputURL.lastPathComponent : nil,
                                    successFallbackText: models.count > 1 ? model.inputURL.lastPathComponent : nil,
                                    collapsesAfterCompletion: models.count > 1
                                ) {
                                    await apply(model).map { [$0] }
                                } onComplete: { results in
                                    guard let result = results.first else { return }
                                    complete(model: model, result: result)
                                }
                                .frame(width: completedModelIDs.contains(model.id) ? 0 : columnWidth)
                                .opacity(activeReflows > 0 && !completedModelIDs.contains(model.id) ? 0.76 : 1)
                                .clipped()
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadImagesSequentially()
        }
    }

    private func loadImagesSequentially() async {
        if models.count > 1, applyScope == .all {
            await sharedModel.loadImage()
        }
        for model in models {
            guard !Task.isCancelled else { return }
            await model.loadImage()
        }
        if models.count > 1, sharedModel.isLoadingImage {
            await sharedModel.loadImage()
        }
    }

    private func setApplyScope(_ scope: ResizeApplyScope) {
        guard applyScope != scope else { return }
        applyScope = scope
        let width = scope == .all
            ? Self.singleWidth
            : Self.multiColumnWidth * CGFloat(min(models.count, 3))
        resizeWindow(width, 0.2)
    }

    private func complete(model: ImageCompressModel, result: ImageCompressResult) {
        guard models.count > 1 else {
            close()
            reveal([result.outputURL])
            return
        }

        let remainingCount = models.count - completedModelIDs.count - 1
        guard remainingCount > 0 else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                close()
                reveal([result.outputURL])
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.24)) {
            activeReflows += 1
            completedModelIDs.insert(model.id)
        }
        resizeWindow(Self.multiColumnWidth * CGFloat(min(remainingCount, 3)), 0.24)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            withAnimation(.easeOut(duration: 0.14)) {
                activeReflows = max(0, activeReflows - 1)
            }
            try? await Task.sleep(for: .milliseconds(140))
            reveal([result.outputURL])
        }
    }
}

private struct ImageCompressColumn: View {
    @ObservedObject var model: ImageCompressModel
    let width: CGFloat
    let detailText: String?
    let successFallbackText: String?
    let collapsesAfterCompletion: Bool
    let apply: () async -> [ImageCompressResult]?
    let onComplete: ([ImageCompressResult]) -> Void

    @State private var isEditorVisible = true
    @State private var isSuccessVisible = false
    @State private var isColumnVisible = true
    @State private var successDetail: String?

    var body: some View {
        ZStack {
            OverlayPanelDragHandle()
                .frame(width: width, height: ImageCompressView.contentHeight)

            VStack(spacing: 0) {
                ImageCompressContent(model: model)
                Divider().opacity(0.36)
                HStack {
                    if let detailText {
                        Text(detailText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(model.isApplying ? "Compressing..." : "Apply") {
                        Task { await applyWithCompletionTransition() }
                    }
                    .font(.system(size: 11, weight: .bold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.isLoadingImage || model.isApplying || !model.isSupported || !isEditorVisible)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
            }
            .opacity(isEditorVisible ? 1 : 0)
            .scaleEffect(isEditorVisible ? 1 : 0.9)
            .compositingGroup()
            .allowsHitTesting(isEditorVisible)

            ImageCompressSuccessView(detail: successDetail ?? successFallbackText)
                .opacity(isSuccessVisible ? 1 : 0)
                .scaleEffect(isSuccessVisible ? 1 : 0.82)
                .compositingGroup()
                .allowsHitTesting(false)
                .accessibilityHidden(!isSuccessVisible)
        }
        .frame(width: width)
        .frame(height: ImageCompressView.contentHeight)
        .opacity(isColumnVisible ? 1 : 0)
        .scaleEffect(isColumnVisible ? 1 : 0.9)
        .compositingGroup()
    }

    private func applyWithCompletionTransition() async {
        guard isEditorVisible, !isSuccessVisible else { return }
        guard let results = await apply() else { return }
        successDetail = successText(for: results)
        withAnimation(.easeInOut(duration: 0.18)) {
            isEditorVisible = false
        }
        try? await Task.sleep(for: .milliseconds(110))
        withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
            isSuccessVisible = true
        }
        try? await Task.sleep(for: .milliseconds(350))
        if collapsesAfterCompletion {
            withAnimation(.easeInOut(duration: 0.15)) {
                isColumnVisible = false
            }
            onComplete(results)
            try? await Task.sleep(for: .milliseconds(150))
            return
        }
        onComplete(results)
    }

    private func successText(for results: [ImageCompressResult]) -> String? {
        if results.count > 1 {
            let savedBytes = results.reduce(Int64(0)) { $0 + $1.savedBytes }
            let inputBytes = results.reduce(Int64(0)) { $0 + $1.inputBytes }
            let percent = inputBytes > 0 ? Int((Double(savedBytes) / Double(inputBytes) * 100).rounded()) : 0
            return "Saved \(ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file)) (\(max(0, percent))%)"
        }
        guard let result = results.first else { return nil }
        return "Saved \(ByteCountFormatter.string(fromByteCount: result.savedBytes, countStyle: .file)) (\(result.savedPercent)%)"
    }
}

private struct ImageCompressContent: View {
    @ObservedObject var model: ImageCompressModel

    var body: some View {
        let previewSize = model.previewSize(fitting: CGSize(width: 320, height: 210))
        VStack(spacing: 12) {
            ImageCompressPreview(model: model)
                .frame(width: previewSize.width, height: previewSize.height)
            ImageCompressControls(model: model)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

private struct ImageCompressPreview: View {
    @ObservedObject var model: ImageCompressModel
    @State private var showsOriginal = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.08))
            if let image = displayedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                if model.isLoadingPreview, !showsOriginal {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(displayedSize)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Color.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 5))
            .padding(6)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in showsOriginal = true }
                .onEnded { _ in showsOriginal = false }
        )
        .accessibilityLabel(showsOriginal ? "Original image" : "Compressed preview")
        .accessibilityHint("Press and hold to compare with original")
        .compositingGroup()
    }

    private var displayedImage: NSImage? {
        showsOriginal ? model.previewImage : (model.compressedPreviewImage ?? model.previewImage)
    }

    private var displayedSize: String {
        if showsOriginal { return model.formattedInputSize }
        if let formattedPreviewSize = model.formattedPreviewSize { return formattedPreviewSize }
        return model.isLoadingPreview ? "Calculating..." : model.formattedInputSize
    }
}

private struct ImageCompressControls: View {
    @ObservedObject var model: ImageCompressModel

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Text("Original")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(originalDetail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Defaults") { model.reset() }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            }

            HStack(spacing: 8) {
                Text("Quality")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 42, alignment: .leading)
                CompressQualitySlider(
                    value: $model.quality,
                    isEnabled: model.supportsQuality,
                    onEditingEnded: model.requestPreview
                )
                if model.supportsQuality {
                    CompressQualityNumberField(
                        value: $model.quality,
                        onEditingEnded: model.requestPreview
                    )
                    .frame(width: 44)
                    Text("%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Lossless")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }

            Toggle("Strip metadata", isOn: Binding(
                get: { model.stripsMetadata },
                set: { model.setStripsMetadata($0) }
            ))
                .font(.system(size: 10, weight: .medium))

            if !model.isSupported {
                Text("Compress does not support this image format yet.")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var originalDetail: String {
        guard model.pixelSize != .zero else { return "Loading..." }
        return "\(Int(model.pixelSize.width)) x \(Int(model.pixelSize.height)) px · \(model.formattedInputSize)"
    }
}

private struct CompressQualitySlider: NSViewRepresentable {
    @Binding var value: Double
    let isEnabled: Bool
    let onEditingEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MouseUpSlider {
        let slider = MouseUpSlider()
        slider.cell = SmallKnobSliderCell()
        slider.minValue = 1
        slider.maxValue = 100
        slider.doubleValue = value
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.controlSize = .small
        slider.isContinuous = true
        slider.onEditingEnded = context.coordinator.editingEnded
        return slider
    }

    func updateNSView(_ slider: MouseUpSlider, context: Context) {
        context.coordinator.parent = self
        slider.doubleValue = value
        slider.isEnabled = isEnabled
        slider.onEditingEnded = context.coordinator.editingEnded
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: CompressQualitySlider

        init(parent: CompressQualitySlider) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: NSSlider) {
            parent.value = sender.doubleValue.rounded()
        }

        func editingEnded() {
            parent.onEditingEnded()
        }
    }
}

private final class MouseUpSlider: NSSlider {
    var onEditingEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onEditingEnded?()
    }
}

private final class SmallKnobSliderCell: NSSliderCell {
    override func knobRect(flipped: Bool) -> NSRect {
        let rect = super.knobRect(flipped: flipped)
        let side = min(rect.width, rect.height, 10)
        return NSRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )
    }
}

private struct CompressQualityNumberField: NSViewRepresentable {
    @Binding var value: Double
    let onEditingEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.alignment = .right
        field.font = .systemFont(ofSize: 11, weight: .medium)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        let text = String(Int(value.rounded()))
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CompressQualityNumberField

        init(_ parent: CompressQualityNumberField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let filtered = field.stringValue.filter { $0.isASCII && $0.isNumber }
            if filtered != field.stringValue {
                field.stringValue = filtered
                field.currentEditor()?.string = filtered
            }
            guard let value = Double(filtered) else { return }
            parent.value = min(max(value, 1), 100)
            let clamped = String(Int(parent.value.rounded()))
            if clamped != filtered {
                field.stringValue = clamped
                field.currentEditor()?.string = clamped
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            field.stringValue = String(Int(parent.value.rounded()))
            parent.onEditingEnded()
        }
    }
}

private struct ImageCompressSuccessView: View {
    let detail: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.green)
            Text("Completed")
                .font(.system(size: 14, weight: .semibold))
            if let detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Image Compress") {
    let model = ImageCompressModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))
    ImageCompressView(models: [model], sharedModel: model) {} apply: { _ in
        ImageCompressResult(
            outputURL: URL(fileURLWithPath: "/tmp/missing-compressed.png"),
            inputBytes: 1_000_000,
            outputBytes: 640_000
        )
    } applyAll: { _, _ in
        [ImageCompressResult(
            outputURL: URL(fileURLWithPath: "/tmp/missing-compressed.png"),
            inputBytes: 1_000_000,
            outputBytes: 640_000
        )]
    } reveal: { _ in } resizeWindow: { _, _ in }
        .frame(width: ImageCompressView.singleWidth, height: ImageCompressView.panelHeight)
        .background(.regularMaterial)
}
#endif
