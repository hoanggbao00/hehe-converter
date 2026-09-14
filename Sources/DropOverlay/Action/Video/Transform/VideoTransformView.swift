import AVFoundation
import SwiftUI

struct VideoTransformView: View {
    static let previewHeight: CGFloat = 240
    static let horizontalPadding: CGFloat = 14

    static func panelWidth(for pixelSize: CGSize) -> CGFloat {
        let aspectRatio = pixelSize.width > 0 && pixelSize.height > 0
            ? pixelSize.width / pixelSize.height
            : 16 / 9
        let previewWidth = max(previewHeight * 4 / 3, previewHeight * aspectRatio)
        return ceil(previewWidth + horizontalPadding * 2)
    }

    @ObservedObject var model: VideoTransformModel
    let close: () -> Void
    let apply: () async -> URL?
    let reveal: (URL) -> Void
    let complete: () -> Void

    var body: some View {
        OverlayPanelView(title: "Transform Video", close: close, actions: []) {
            VStack(spacing: 0) {
                VideoTransformPreview(model: model)
                    .frame(width: previewSize.width, height: previewSize.height)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 12)

                VideoTransformPlaybackControls(model: model)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 8)

                VideoTransformControls(model: model)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 12)

                Color.clear.frame(height: 8)
                Divider().opacity(0.36)
                HStack {
                    Text(model.inputURL.lastPathComponent)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(model.isApplying ? "Transforming..." : "Apply") {
                        Task {
                            guard let outputURL = await apply() else { return }
                            reveal(outputURL)
                            complete()
                        }
                    }
                    .font(.system(size: 11, weight: .bold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.isLoading || model.isApplying || !model.canApply)
                }
                .padding(.horizontal, Self.horizontalPadding)
                .frame(height: 40)
            }
        }
        .task { await model.load() }
        .onDisappear { model.player.pause() }
    }

    private var previewSize: CGSize {
        CGSize(
            width: Self.panelWidth(for: model.pixelSize) - Self.horizontalPadding * 2,
            height: Self.previewHeight
        )
    }
}

struct VideoTransformPreview: View {
    @ObservedObject var model: VideoTransformModel
    @State private var resizeStartSize: CGSize?
    @State private var isResizing = false

    var body: some View {
        GeometryReader { geometry in
            let videoRect = fittedRect(for: model.pixelSize, in: geometry.size)
            let previewRect = model.previewRect(in: videoRect)

            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.black.opacity(0.08))
                    .frame(width: videoRect.width, height: videoRect.height)
                    .position(x: videoRect.midX, y: videoRect.midY)

                PlayerLayerView(player: model.player, videoGravity: .resize)
                    .frame(width: previewRect.width, height: previewRect.height)
                    .scaleEffect(x: model.flipsHorizontally ? -1 : 1, y: model.flipsVertically ? -1 : 1)
                    .clipShape(.rect)
                    .position(x: previewRect.midX, y: previewRect.midY)

                Rectangle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: previewRect.width, height: previewRect.height)
                    .position(x: previewRect.midX, y: previewRect.midY)
                    .shadow(color: .black.opacity(0.22), radius: 1)

                ForEach(ResizeHandlePosition.allCases) { handle in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .overlay { RoundedRectangle(cornerRadius: 2).stroke(.black.opacity(0.18), lineWidth: 1) }
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .position(handle.point(in: previewRect))
                        .gesture(resizeGesture(handle: handle, in: videoRect.size))
                }

                if model.isLoading { ProgressView().controlSize(.small) }
            }
            .overlay(alignment: .bottomTrailing) {
                let output = model.outputPixelSize
                Text("\(Int(output.width)) x \(Int(output.height))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 5))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .compositingGroup()
    }

    private func resizeGesture(handle: ResizeHandlePosition, in videoRectSize: CGSize) -> some Gesture {
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
                    in: videoRectSize
                )
            }
            .onEnded { _ in
                resizeStartSize = nil
                isResizing = false
            }
    }

    private func fittedRect(for size: CGSize, in available: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: available) }
        let scale = min(available.width / size.width, available.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: (available.width - fitted.width) / 2,
            y: (available.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}

private struct VideoTransformPlaybackControls: View {
    @ObservedObject var model: VideoTransformModel

    var body: some View {
        HStack(spacing: 5) {
            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

            Text(model.formattedCurrentTime)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .frame(width: 32, alignment: .trailing)

            Slider(
                value: Binding(get: { model.currentTime }, set: { model.setCurrentTime($0) }),
                in: 0...max(model.duration, 0.001),
                onEditingChanged: model.setSeeking
            )
            .controlSize(.mini)
            .accessibilityLabel("Video position")

            Text(model.formattedDuration)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .frame(width: 32, alignment: .leading)
        }
    }
}

private struct VideoTransformControls: View {
    @ObservedObject var model: VideoTransformModel

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
                .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
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
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))

                Picker("Unit", selection: Binding(
                    get: { model.unit },
                    set: { model.applyUnit($0) }
                )) {
                    ForEach(ImageDimensionUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 58)
            }

            HStack(spacing: 8) {
                Toggle("Flip horizontal", isOn: $model.flipsHorizontally)
                    .toggleStyle(.checkbox)
                Toggle("Flip vertical", isOn: $model.flipsVertically)
                    .toggleStyle(.checkbox)
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, weight: .medium))

            VideoTransformDimensionControl(
                title: "Width",
                value: Binding(get: { model.width }, set: { model.setWidth($0) }),
                unit: model.unit,
                range: model.range(for: .horizontal)
            )
            VideoTransformDimensionControl(
                title: "Height",
                value: Binding(get: { model.height }, set: { model.setHeight($0) }),
                unit: model.unit,
                range: model.range(for: .vertical)
            )

            HStack {
                Text("Output")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                let output = model.outputPixelSize
                Text("\(Int(output.width)) x \(Int(output.height)) px")
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

struct VideoTransformDimensionControl: View {
    let title: String
    @Binding var value: Double
    let unit: ImageDimensionUnit
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 38, alignment: .leading)
            ActionSlider(value: $value, range: range)
            VideoTransformNumberField(value: $value, range: range)
                .frame(width: 50, height: 20)
            Text(unit.rawValue)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 14, alignment: .leading)
        }
    }
}

struct VideoTransformNumberField: NSViewRepresentable {
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
        var parent: VideoTransformNumberField

        init(_ parent: VideoTransformNumberField) {
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
#Preview("Video Transform") {
    VideoTransformView(model: VideoTransformModel(inputURL: URL(fileURLWithPath: "/tmp/missing.mp4"))) {} apply: {
        URL(fileURLWithPath: "/tmp/missing-transformed.mp4")
    } reveal: { _ in }
      complete: {}
        .frame(width: VideoTransformView.panelWidth(for: CGSize(width: 1920, height: 1080)))
        .background(.regularMaterial)
}
#endif
