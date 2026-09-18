import AVFoundation
import AppKit
import SwiftUI

struct VideoCropView: View {
    static let previewHeight: CGFloat = 240
    static let horizontalPadding: CGFloat = 14

    static func panelWidth(for pixelSize: CGSize) -> CGFloat {
        let aspectRatio = pixelSize.width > 0 && pixelSize.height > 0
            ? pixelSize.width / pixelSize.height
            : 16 / 9
        let previewWidth = max(previewHeight * 4 / 3, previewHeight * aspectRatio)
        return ceil(previewWidth + horizontalPadding * 2)
    }

    @ObservedObject var model: VideoCropModel
    let close: () -> Void
    let apply: () async -> URL?
    let reveal: (URL) -> Void
    let complete: () -> Void

    var body: some View {
        OverlayPanelView(title: "Crop Video", close: close, actions: []) {
            VStack(spacing: 0) {
                VideoCropPreview(model: model)
                    .frame(width: previewSize.width, height: previewSize.height)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                VideoPlaybackControls(model: model)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                VideoCropControls(model: model)
                    .padding(.horizontal, 14)
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
                    Button(model.isApplying ? "Cropping..." : "Apply") {
                        Task {
                            guard let outputURL = await apply() else { return }
                            reveal(outputURL)
                            complete()
                        }
                    }
                    .font(.system(size: 11, weight: .bold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.isLoading || model.isApplying)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
            }
        }
        .task { await model.load() }
        .onDisappear { model.player.pause() }
    }

    private var previewSize: CGSize {
        return CGSize(
            width: Self.panelWidth(for: model.pixelSize) - Self.horizontalPadding * 2,
            height: Self.previewHeight
        )
    }
}

private struct VideoCropPreview: View {
    @ObservedObject var model: VideoCropModel
    @State private var dragStartCenter: CGPoint?
    @State private var resizeStartRect: CGRect?

    var body: some View {
        GeometryReader { geometry in
            let videoRect = fittedRect(for: model.pixelSize, in: geometry.size)
            let cropRect = model.cropRect(in: videoRect)

            ZStack {
                PlayerLayerView(player: model.player)
                    .frame(width: videoRect.width, height: videoRect.height)
                    .background(.black, in: RoundedRectangle(cornerRadius: 4))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .position(x: videoRect.midX, y: videoRect.midY)

                VideoCropScrim(videoRect: videoRect, cropRect: cropRect)
                    .fill(.black.opacity(0.46), style: FillStyle(eoFill: true))

                VideoCropGrid()
                    .stroke(.white.opacity(0.75), lineWidth: 0.7)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)

                Rectangle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .gesture(moveGesture(in: videoRect))

                ForEach(CropHandlePosition.allCases) { handle in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .overlay { RoundedRectangle(cornerRadius: 2).stroke(.black.opacity(0.18)) }
                        .frame(width: handle.isCorner ? 12 : 10, height: handle.isCorner ? 12 : 10)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .position(handle.point(in: cropRect))
                        .gesture(resizeGesture(handle: handle, in: videoRect))
                }

                if model.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private func moveGesture(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartCenter == nil { dragStartCenter = model.cropCenter }
                guard let dragStartCenter, rect.width > 0, rect.height > 0 else { return }
                model.moveCrop(
                    from: dragStartCenter,
                    translation: CGSize(
                        width: value.translation.width / rect.width,
                        height: value.translation.height / rect.height
                    )
                )
            }
            .onEnded { _ in dragStartCenter = nil }
    }

    private func resizeGesture(handle: CropHandlePosition, in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizeStartRect == nil { resizeStartRect = model.normalizedCropRect() }
                guard let resizeStartRect, rect.width > 0, rect.height > 0 else { return }
                model.resizeCrop(
                    handle: handle,
                    from: resizeStartRect,
                    translation: CGSize(
                        width: value.translation.width / rect.width,
                        height: value.translation.height / rect.height
                    )
                )
            }
            .onEnded { _ in resizeStartRect = nil }
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

private struct VideoPlaybackControls: View {
    @ObservedObject var model: VideoCropModel

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

private struct VideoCropControls: View {
    @ObservedObject var model: VideoCropModel

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Text("Aspect ratio")
                    .font(.system(size: 11, weight: .medium))
                HStack(spacing: 8) {
                    Picker("Aspect ratio", selection: Binding(
                        get: { model.aspectRatio },
                        set: { model.applyAspectRatio($0) }
                    )) {
                        ForEach(CropAspectRatio.allCases) { ratio in Text(ratio.rawValue).tag(ratio) }
                    }
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    Picker("Unit", selection: Binding(
                        get: { model.unit },
                        set: { model.applyUnit($0) }
                    )) {
                        ForEach(CropDimensionUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                    }
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack {
                Button("Reset") { model.reset() }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                Spacer()
                Text("\(Int(model.pixelSize.width)) x \(Int(model.pixelSize.height)) px · \(model.formattedInputSize)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VideoCropDimensionControl(
                title: "Width",
                value: Binding(get: { model.width }, set: { model.setWidth($0) }),
                unit: model.unit,
                range: model.unit.range(for: model.pixelSize, axis: .horizontal)
            )
            VideoCropDimensionControl(
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

private struct VideoCropDimensionControl: View {
    let title: String
    @Binding var value: Double
    let unit: CropDimensionUnit
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 38, alignment: .leading)
            Slider(value: $value, in: range)
                .controlSize(.mini)
            VideoCropNumberField(value: $value, range: range)
                .frame(width: 46, height: 20)
            Text(unit.rawValue)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 14, alignment: .leading)
        }
    }
}

private struct VideoCropNumberField: NSViewRepresentable {
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
        var parent: VideoCropNumberField

        init(_ parent: VideoCropNumberField) {
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

struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateNSView(_ view: PlayerNSView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
    }
}

final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer = playerLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

private struct VideoCropScrim: Shape {
    let videoRect: CGRect
    let cropRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(videoRect)
        path.addRect(cropRect)
        return path
    }
}

private struct VideoCropGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 1...2 {
            let position = CGFloat(index) / 3
            path.move(to: CGPoint(x: rect.width * position, y: 0))
            path.addLine(to: CGPoint(x: rect.width * position, y: rect.height))
            path.move(to: CGPoint(x: 0, y: rect.height * position))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * position))
        }
        return path
    }
}

#if DEBUG
#Preview("Video Crop") {
    VideoCropView(model: VideoCropModel(inputURL: URL(fileURLWithPath: "/tmp/missing.mp4"))) {} apply: {
        URL(fileURLWithPath: "/tmp/missing-cropped.mp4")
    } reveal: { _ in }
      complete: {}
        .frame(width: VideoCropView.panelWidth(for: CGSize(width: 1920, height: 1080)))
        .background(.regularMaterial)
}
#endif
