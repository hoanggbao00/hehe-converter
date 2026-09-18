import AppKit
import SwiftUI

struct ImageCropView: View {
    static let singleWidth: CGFloat = 360
    static let multiColumnWidth: CGFloat = 320
    static let panelHeight: CGFloat = 458
    static let headerHeight: CGFloat = 48
    static let contentHeight = panelHeight - headerHeight

    let models: [ImageCropModel]
    let close: () -> Void
    let apply: (ImageCropModel) async -> URL?
    let reveal: (URL) -> Void
    let resizeWindow: (CGFloat, TimeInterval) -> Void

    @State private var completedModelIDs: Set<ImageCropModel.ID> = []
    @State private var activeReflows = 0

    private var columnWidth: CGFloat {
        models.count == 1 ? Self.singleWidth : Self.multiColumnWidth
    }

    private var showsFilenames: Bool {
        models.count > 1
    }

    var body: some View {
        OverlayPanelView(
            title: "Crop Image",
            close: close,
            actions: []
        ) {
            ScrollView(.horizontal) {
                HStack(spacing: 1) {
                    ForEach(models) { model in
                        ImageCropColumn(
                            model: model,
                            width: columnWidth,
                            showsFilename: showsFilenames,
                            collapsesAfterCompletion: models.count > 1
                        ) {
                            await apply(model)
                        } onComplete: { outputURL in
                            complete(model: model, outputURL: outputURL)
                        }
                        .frame(width: completedModelIDs.contains(model.id) ? 0 : columnWidth)
                        .opacity(activeReflows > 0 && !completedModelIDs.contains(model.id) ? 0.76 : 1)
                        .clipped()
                    }
                }
            }
        }
        .task {
            for model in models {
                guard !Task.isCancelled else { return }
                await model.loadImage()
            }
        }
    }

    private func complete(model: ImageCropModel, outputURL: URL) {
        guard models.count > 1 else {
            close()
            reveal(outputURL)
            return
        }

        let remainingCount = models.count - completedModelIDs.count - 1
        guard remainingCount > 0 else {
            Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
                close()
                reveal(outputURL)
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
            do {
                try await Task.sleep(for: .milliseconds(240))
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.14)) {
                activeReflows = max(0, activeReflows - 1)
            }
            try? await Task.sleep(for: .milliseconds(140))
            reveal(outputURL)
        }
    }
}

private struct ImageCropColumn: View {
    @ObservedObject var model: ImageCropModel
    let width: CGFloat
    let showsFilename: Bool
    let collapsesAfterCompletion: Bool
    let apply: () async -> URL?
    let onComplete: (URL) -> Void

    @State private var isEditorVisible = true
    @State private var isSuccessVisible = false
    @State private var isColumnVisible = true

    var body: some View {
        ZStack {
            OverlayPanelDragHandle()
                .frame(width: width, height: ImageCropView.contentHeight)

            VStack(spacing: 0) {
                ImageCropContent(model: model)
                Divider().opacity(0.36)
                HStack {
                    if showsFilename {
                        Text(model.inputURL.lastPathComponent)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(model.isApplying ? "Cropping..." : "Apply") {
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

            ImageCropSuccessView(filename: showsFilename ? model.inputURL.lastPathComponent : nil)
                .opacity(isSuccessVisible ? 1 : 0)
                .scaleEffect(isSuccessVisible ? 1 : 0.82)
                .compositingGroup()
                .allowsHitTesting(false)
                .accessibilityHidden(!isSuccessVisible)
        }
        .frame(width: width)
        .frame(height: ImageCropView.contentHeight)
        .opacity(isColumnVisible ? 1 : 0)
        .scaleEffect(isColumnVisible ? 1 : 0.9)
        .compositingGroup()
    }

    private func applyWithCompletionTransition() async {
        guard isEditorVisible, !isSuccessVisible else { return }
        guard let outputURL = await apply() else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            isEditorVisible = false
        }
        do {
            try await Task.sleep(for: .milliseconds(110))
        } catch {
            return
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
            isSuccessVisible = true
        }
        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            return
        }
        if collapsesAfterCompletion {
            withAnimation(.easeInOut(duration: 0.15)) {
                isColumnVisible = false
            }
            onComplete(outputURL)
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            return
        }
        onComplete(outputURL)
    }
}

private struct ImageCropSuccessView: View {
    let filename: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.green)
            Text("Completed")
                .font(.system(size: 14, weight: .semibold))
            if let filename {
                Text(filename)
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

private struct ImageCropContent: View {
    @ObservedObject var model: ImageCropModel

    var body: some View {
        let previewSize = model.previewSize(fitting: CGSize(width: 280, height: 210))
        VStack(spacing: 12) {
            DraggableCropPreview(model: model)
                .frame(width: previewSize.width, height: previewSize.height)
            ImageCropControls(model: model)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

private struct ImageCropControls: View {
    @ObservedObject var model: ImageCropModel

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Text("Aspect ratio")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 72, alignment: .leading)
                Spacer(minLength: 0)
                Picker("Aspect ratio", selection: Binding(
                    get: { model.aspectRatio },
                    set: {
                        model.applyAspectRatio($0)
                        model.requestPreviewSize()
                    }
                )) {
                    ForEach(CropAspectRatio.allCases) { ratio in
                        Text(ratio.rawValue).tag(ratio)
                    }
                }
                .labelsHidden()
                .frame(width: 126)

                Picker("Unit", selection: Binding(
                    get: { model.unit },
                    set: {
                        model.applyUnit($0)
                        model.requestPreviewSize()
                    }
                )) {
                    ForEach(CropDimensionUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 58)
            }

            HStack {
                Button("Reset") { model.reset() }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                Spacer()
                Text("\(Int(model.pixelSize.width)) x \(Int(model.pixelSize.height)) px · \(model.formattedInputSize)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            CropDimensionControl(
                title: "Width",
                value: Binding(get: { model.width }, set: { model.setWidth($0) }),
                unit: model.unit,
                range: model.unit.range(for: model.pixelSize, axis: .horizontal),
                onEditingEnded: model.requestPreviewSize
            )
            CropDimensionControl(
                title: "Height",
                value: Binding(get: { model.height }, set: { model.setHeight($0) }),
                unit: model.unit,
                range: model.unit.range(for: model.pixelSize, axis: .vertical),
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
                let output = model.pixelCropRect().size
                Text("\(Int(output.width)) x \(Int(output.height)) px · \(model.formattedPreviewSize)")
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

private struct DraggableCropPreview: View {
    @ObservedObject var model: ImageCropModel
    @State private var dragStartCenter: CGPoint?
    @State private var resizeStartRect: CGRect?

    var body: some View {
        GeometryReader { geometry in
            let imageRect = previewImageRect(in: geometry.size)
            let cropRect = model.cropRect(in: imageRect)

            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.08))

                if let image = model.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                }

                CropScrim(imageRect: imageRect, cropRect: cropRect)
                    .fill(Color.black.opacity(0.36), style: FillStyle(eoFill: true))

                CropGrid()
                    .stroke(Color.white.opacity(0.78), lineWidth: 0.7)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)

                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .shadow(color: .black.opacity(0.25), radius: 1)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .gesture(moveGesture(in: imageRect))

                ForEach(CropHandlePosition.allCases) { handle in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: handle.isCorner ? 12 : 10, height: handle.isCorner ? 12 : 10)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.black.opacity(0.18), lineWidth: 1)
                        }
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .position(handle.point(in: cropRect))
                        .gesture(resizeGesture(handle: handle, in: imageRect))
                }
            }
        }
    }

    private func moveGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartCenter == nil {
                    dragStartCenter = model.cropCenter
                }
                guard let dragStartCenter else { return }
                model.moveCrop(
                    from: dragStartCenter,
                    translation: CGSize(
                        width: value.translation.width / imageRect.width,
                        height: value.translation.height / imageRect.height
                    )
                )
            }
            .onEnded { _ in
                dragStartCenter = nil
                model.requestPreviewSize()
            }
    }

    private func resizeGesture(handle: CropHandlePosition, in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizeStartRect == nil {
                    resizeStartRect = model.normalizedCropRect()
                }
                guard let resizeStartRect else { return }
                model.resizeCrop(
                    handle: handle,
                    from: resizeStartRect,
                    translation: CGSize(
                        width: value.translation.width / imageRect.width,
                        height: value.translation.height / imageRect.height
                    )
                )
            }
            .onEnded { _ in
                resizeStartRect = nil
                model.requestPreviewSize()
            }
    }

    private func previewImageRect(in availableSize: CGSize) -> CGRect {
        guard model.pixelSize.width > 0, model.pixelSize.height > 0 else {
            return CGRect(origin: .zero, size: availableSize)
        }
        let scale = min(availableSize.width / model.pixelSize.width, availableSize.height / model.pixelSize.height)
        let size = CGSize(width: model.pixelSize.width * scale, height: model.pixelSize.height * scale)
        return CGRect(
            x: (availableSize.width - size.width) / 2,
            y: (availableSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

private struct CropScrim: Shape {
    let imageRect: CGRect
    let cropRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(imageRect)
        path.addRect(cropRect)
        return path
    }
}

private struct CropGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 1...2 {
            let x = rect.width * CGFloat(index) / 3
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))

            let y = rect.height * CGFloat(index) / 3
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

private struct CropDimensionControl: View {
    let title: String
    @Binding var value: Double
    let unit: CropDimensionUnit
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
                CropPixelNumberField(value: $value, range: range, onEditingEnded: onEditingEnded)
                    .frame(width: 82)
                Text("px")
                    .font(.system(size: 10, weight: .medium))
            }
        }
    }
}

private struct CropPixelNumberField: NSViewRepresentable {
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
        var parent: CropPixelNumberField

        init(_ parent: CropPixelNumberField) {
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

#if DEBUG
#Preview("Image Crop") {
    ImageCropView(models: [ImageCropModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))]) {} apply: { _ in
        URL(fileURLWithPath: "/tmp/missing-cropped.png")
    } reveal: { _ in } resizeWindow: { _, _ in }
        .frame(width: ImageCropView.singleWidth, height: ImageCropView.panelHeight)
        .background(.regularMaterial)
}
#endif
