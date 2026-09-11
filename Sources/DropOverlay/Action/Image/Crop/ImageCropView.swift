import AppKit
import SwiftUI

struct ImageCropView: View {
    @ObservedObject var model: ImageCropModel
    let close: () -> Void
    let apply: () async -> Void

    var body: some View {
        OverlayPanelView(
            title: "Crop Image",
            close: close,
            actions: [
                OverlayPanelAction(
                    label: model.isApplying ? "Cropping..." : "Apply",
                    action: { Task { await apply() } },
                    variant: .primary,
                    isEnabled: !model.isApplying
                )
            ]
        ) {
            let previewSize = model.previewSize(fitting: CGSize(width: 280, height: 210))
            VStack(spacing: 12) {
                DraggableCropPreview(model: model)
                    .frame(width: previewSize.width, height: previewSize.height)
                ImageCropControls(model: model)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
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
                    set: { model.applyAspectRatio($0) }
                )) {
                    ForEach(CropAspectRatio.allCases) { ratio in
                        Text(ratio.rawValue).tag(ratio)
                    }
                }
                .labelsHidden()
                .frame(width: 126)

                Picker("Unit", selection: Binding(
                    get: { model.unit },
                    set: { model.applyUnit($0) }
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
                Text("\(Int(model.pixelSize.width)) x \(Int(model.pixelSize.height)) px")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            CropDimensionControl(
                title: "Width",
                value: Binding(get: { model.width }, set: { model.setWidth($0) }),
                unit: model.unit,
                range: model.unit.range(for: model.pixelSize, axis: .horizontal)
            )
            CropDimensionControl(
                title: "Height",
                value: Binding(get: { model.height }, set: { model.setHeight($0) }),
                unit: model.unit,
                range: model.unit.range(for: model.pixelSize, axis: .vertical)
            )

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

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 34, alignment: .leading)
            switch unit {
            case .percent:
                Slider(value: $value, in: range, step: 1)
                    .tint(Color(red: 0.92, green: 0.24, blue: 0.09))
                Text("\(Int(value))%")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 44, alignment: .trailing)
            case .pixels:
                Spacer()
                CropPixelNumberField(value: $value, range: range)
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
        }
    }
}

#if DEBUG
#Preview("Image Crop") {
    ImageCropView(model: ImageCropModel(inputURL: URL(fileURLWithPath: "/tmp/missing.png"))) {} apply: {}
        .frame(width: 360, height: 470)
        .background(.regularMaterial)
}
#endif
