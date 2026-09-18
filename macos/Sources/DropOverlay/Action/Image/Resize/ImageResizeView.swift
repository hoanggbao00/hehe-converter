import AppKit
import SwiftUI

struct ImageResizeView: View {
    static let singleWidth: CGFloat = 340
    static let multiColumnWidth: CGFloat = 300
    static let panelHeight: CGFloat = 384
    static let headerHeight: CGFloat = 48
    static let contentHeight = panelHeight - headerHeight

    let models: [ImageResizeModel]
    let sharedModel: ImageResizeModel
    let close: () -> Void
    let apply: (ImageResizeModel) async -> URL?
    let applyAll: (ImageResizeModel, [ImageResizeModel]) async -> [URL]?
    let reveal: ([URL]) -> Void
    let resizeWindow: (CGFloat, TimeInterval) -> Void

    @State private var applyScope: ResizeApplyScope
    @State private var completedModelIDs: Set<ImageResizeModel.ID> = []
    @State private var activeReflows = 0

    init(
        models: [ImageResizeModel],
        sharedModel: ImageResizeModel,
        defaultScope: ResizeApplyScope,
        close: @escaping () -> Void,
        apply: @escaping (ImageResizeModel) async -> URL?,
        applyAll: @escaping (ImageResizeModel, [ImageResizeModel]) async -> [URL]?,
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
        _applyScope = State(initialValue: models.count > 1 ? defaultScope : .each)
    }

    private var columnWidth: CGFloat {
        models.count == 1 ? Self.singleWidth : Self.multiColumnWidth
    }

    private var showsFilenames: Bool {
        models.count > 1
    }

    var body: some View {
        OverlayPanelView(
            title: "Resize Image",
            close: close,
            actions: []
        ) {
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
                    ImageResizeColumn(
                        model: sharedModel,
                        width: Self.singleWidth,
                        detailText: "Applies to \(models.count) images",
                        successText: "\(models.count) images resized",
                        collapsesAfterCompletion: false
                    ) {
                        await applyAll(sharedModel, models)
                    } onComplete: { outputURLs in
                        close()
                        reveal(outputURLs)
                    }
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 1) {
                            ForEach(models) { model in
                                ImageResizeColumn(
                                    model: model,
                                    width: columnWidth,
                                    detailText: showsFilenames ? model.inputURL.lastPathComponent : nil,
                                    successText: showsFilenames ? model.inputURL.lastPathComponent : nil,
                                    collapsesAfterCompletion: models.count > 1
                                ) {
                                    await apply(model).map { [$0] }
                                } onComplete: { outputURLs in
                                    guard let outputURL = outputURLs.first else { return }
                                    complete(model: model, outputURL: outputURL)
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

    private func complete(model: ImageResizeModel, outputURL: URL) {
        guard models.count > 1 else {
            close()
            reveal([outputURL])
            return
        }

        let remainingCount = models.count - completedModelIDs.count - 1
        guard remainingCount > 0 else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                close()
                reveal([outputURL])
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.24)) {
            activeReflows += 1
            completedModelIDs.insert(model.id)
        }
        let visibleColumns = min(remainingCount, 3)
        resizeWindow(Self.multiColumnWidth * CGFloat(visibleColumns), 0.24)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            withAnimation(.easeOut(duration: 0.14)) {
                activeReflows = max(0, activeReflows - 1)
            }
            try? await Task.sleep(for: .milliseconds(140))
            reveal([outputURL])
        }
    }
}

private struct ImageResizeColumn: View {
    @ObservedObject var model: ImageResizeModel
    let width: CGFloat
    let detailText: String?
    let successText: String?
    let collapsesAfterCompletion: Bool
    let apply: () async -> [URL]?
    let onComplete: ([URL]) -> Void

    @State private var isEditorVisible = true
    @State private var isSuccessVisible = false
    @State private var isColumnVisible = true

    var body: some View {
        ZStack {
            OverlayPanelDragHandle()
                .frame(width: width, height: ImageResizeView.contentHeight)

            VStack(spacing: 0) {
                ImageResizeContent(model: model)
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
                    Button(model.isApplying ? "Resizing..." : "Apply") {
                        Task { await applyWithCompletionTransition() }
                    }
                    .font(.system(size: 11, weight: .bold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.isLoadingImage || model.isApplying || !isEditorVisible)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
            }
            .opacity(isEditorVisible ? 1 : 0)
            .scaleEffect(isEditorVisible ? 1 : 0.9)
            .compositingGroup()
            .allowsHitTesting(isEditorVisible)

            ImageResizeSuccessView(detail: successText)
                .opacity(isSuccessVisible ? 1 : 0)
                .scaleEffect(isSuccessVisible ? 1 : 0.82)
                .compositingGroup()
                .allowsHitTesting(false)
                .accessibilityHidden(!isSuccessVisible)
        }
        .frame(width: width)
        .frame(height: ImageResizeView.contentHeight)
        .opacity(isColumnVisible ? 1 : 0)
        .scaleEffect(isColumnVisible ? 1 : 0.9)
        .compositingGroup()
    }

    private func applyWithCompletionTransition() async {
        guard isEditorVisible, !isSuccessVisible else { return }
        guard let outputURLs = await apply() else { return }
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
            onComplete(outputURLs)
            try? await Task.sleep(for: .milliseconds(150))
            return
        }
        onComplete(outputURLs)
    }
}

private struct ImageResizeContent: View {
    @ObservedObject var model: ImageResizeModel

    var body: some View {
        let previewSize = model.previewSize(fitting: CGSize(width: 252, height: 168))
        VStack(spacing: 12) {
            ImageResizePreview(model: model)
                .frame(width: previewSize.width, height: previewSize.height)
            ImageResizeControls(model: model)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

private struct ImageResizePreview: View {
    @ObservedObject var model: ImageResizeModel
    @State private var resizeStartSize: CGSize?
    @State private var isResizing = false

    var body: some View {
        GeometryReader { geometry in
            let imageRect = CGRect(origin: .zero, size: geometry.size)
            let previewRect = model.previewRect(in: imageRect)

            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.08))

                imageLayer(contentMode: .fit, opacity: isResizing ? 0.22 : 0.42)
                    .overlay(Color.black.opacity(isResizing ? 0.18 : 0.08))
                    .clipShape(.rect(cornerRadius: 4))

                outputImageLayer
                    .frame(width: previewRect.width, height: previewRect.height)
                    .clipShape(.rect)
                    .position(x: previewRect.midX, y: previewRect.midY)

                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: previewRect.width, height: previewRect.height)
                    .position(x: previewRect.midX, y: previewRect.midY)
                    .shadow(color: .black.opacity(0.22), radius: 1)

                ForEach(ResizeHandlePosition.allCases) { handle in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.black.opacity(0.18), lineWidth: 1)
                        }
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .position(handle.point(in: previewRect))
                        .gesture(resizeGesture(handle: handle, in: imageRect.size))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                let output = model.outputPixelSize
                Text("\(Int(output.width)) x \(Int(output.height))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Color.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 5))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .compositingGroup()
    }

    @ViewBuilder
    private var outputImageLayer: some View {
        if let image = model.previewImage {
            Image(nsImage: image)
                .resizable()
        } else {
            Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func imageLayer(contentMode: ContentMode, opacity: Double) -> some View {
        if let image = model.previewImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .opacity(opacity)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)
                .opacity(opacity)
        }
    }

    private func resizeGesture(handle: ResizeHandlePosition, in imageRectSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizeStartSize == nil {
                    resizeStartSize = model.outputPixelSize
                    isResizing = true
                }
                guard let resizeStartSize else { return }
                model.resizePreview(
                    handle: handle,
                    from: resizeStartSize,
                    translation: value.translation,
                    in: imageRectSize
                )
            }
            .onEnded { _ in
                resizeStartSize = nil
                isResizing = false
                model.requestPreviewSize()
            }
    }
}

private struct ImageResizeControls: View {
    @ObservedObject var model: ImageResizeModel

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Button {
                    model.setKeepsAspectRatio(!model.keepsAspectRatio)
                } label: {
                    Image(systemName: model.keepsAspectRatio ? "lock.fill" : "lock.open")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                .accessibilityLabel(model.keepsAspectRatio ? "Unlock aspect ratio" : "Lock aspect ratio")

                Text("Original")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("\(Int(model.pixelSize.width)) x \(Int(model.pixelSize.height)) px · \(model.formattedInputSize)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button("Reset") { model.reset() }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))

                Picker("Unit", selection: Binding(
                    get: { model.unit },
                    set: {
                        model.applyUnit($0)
                        model.requestPreviewSize()
                    }
                )) {
                    ForEach(ImageDimensionUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 58)
            }

            ResizeDimensionControl(
                title: "Width",
                value: Binding(get: { model.width }, set: { model.setWidth($0) }),
                unit: model.unit,
                range: model.range(for: .horizontal),
                onEditingEnded: model.requestPreviewSize
            )
            ResizeDimensionControl(
                title: "Height",
                value: Binding(get: { model.height }, set: { model.setHeight($0) }),
                unit: model.unit,
                range: model.range(for: .vertical),
                onEditingEnded: model.requestPreviewSize
            )

            HStack {
                Text("Output")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isLoadingPreviewSize {
                    ProgressView().controlSize(.mini)
                }
                Text("\(Int(model.outputPixelSize.width)) x \(Int(model.outputPixelSize.height)) px · \(model.formattedPreviewSize)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ResizeDimensionControl: View {
    let title: String
    @Binding var value: Double
    let unit: ImageDimensionUnit
    let range: ClosedRange<Double>
    let onEditingEnded: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 34, alignment: .leading)
            switch unit {
            case .percent:
                ActionSlider(value: $value, range: range, onEditingEnded: onEditingEnded)
                Text("\(Int(value))%")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 44, alignment: .trailing)
            case .pixels:
                Spacer()
                ResizePixelNumberField(value: $value, range: range, onEditingEnded: onEditingEnded)
                    .frame(width: 82)
                Text("px")
                    .font(.system(size: 10, weight: .medium))
            }
        }
    }
}

private struct ResizePixelNumberField: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
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
        var parent: ResizePixelNumberField

        init(_ parent: ResizePixelNumberField) {
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
            parent.value = min(max(value, parent.range.lowerBound), parent.range.upperBound)
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

private struct ImageResizeSuccessView: View {
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
#Preview("Image Resize") {
    let model = ImageResizeModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))
    ImageResizeView(models: [model], sharedModel: model, defaultScope: .all) {} apply: { _ in
        URL(fileURLWithPath: "/tmp/missing-resized.png")
    } applyAll: { _, _ in
        [URL(fileURLWithPath: "/tmp/missing-resized.png")]
    } reveal: { _ in } resizeWindow: { _, _ in }
        .frame(width: ImageResizeView.singleWidth, height: ImageResizeView.panelHeight)
        .background(.regularMaterial)
}
#endif
