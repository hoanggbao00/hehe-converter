import SwiftUI

struct VideoCompressView: View {
    static let width: CGFloat = 430

    @ObservedObject var model: VideoCompressModel
    @ObservedObject private var previewModel: VideoTransformModel
    let fileCount: Int
    let enabledOptions: Set<VideoCompressOption>
    let close: () -> Void
    let apply: (VideoCompressSettings) -> Void

    init(
        model: VideoCompressModel,
        fileCount: Int,
        enabledOptions: Set<VideoCompressOption>,
        close: @escaping () -> Void,
        apply: @escaping (VideoCompressSettings) -> Void
    ) {
        self.model = model
        _previewModel = ObservedObject(wrappedValue: model.preview)
        self.fileCount = fileCount
        self.enabledOptions = enabledOptions
        self.close = close
        self.apply = apply
    }

    var body: some View {
        OverlayPanelView(title: "Compress Video", close: close, actions: []) {
            VStack(spacing: 0) {
                preview
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                controls
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Divider().opacity(0.36)
                HStack {
                    Text(fileCount == 1 ? model.preview.inputURL.lastPathComponent : "\(fileCount) videos")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Compress") { apply(model.settings) }
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(previewModel.isLoading)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
            }
        }
        .task { await model.load() }
        .onDisappear { model.preview.player.pause() }
    }

    private var preview: some View {
        VStack(spacing: 7) {
            VideoTransformPreview(model: previewModel)
                .frame(width: previewSize.width, height: previewSize.height)

            HStack(spacing: 5) {
                Button { previewModel.togglePlayback() } label: {
                    Image(systemName: previewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(previewModel.isPlaying ? "Pause" : "Play")

                Text(previewModel.formattedCurrentTime)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
                Slider(
                    value: Binding(
                        get: { previewModel.currentTime },
                        set: { previewModel.setCurrentTime($0) }
                    ),
                    in: 0...max(previewModel.duration, 0.001),
                    onEditingChanged: previewModel.setSeeking
                )
                .controlSize(.mini)
                .accessibilityLabel("Video position")
                Text(previewModel.formattedDuration)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .frame(width: 32, alignment: .leading)
            }
        }
    }

    private var previewSize: CGSize {
        let aspectRatio = previewModel.pixelSize.width > 0 && previewModel.pixelSize.height > 0
            ? previewModel.pixelSize.width / previewModel.pixelSize.height
            : 16 / 9
        let height: CGFloat = 190
        let maxWidth = Self.width - 28
        return CGSize(width: min(maxWidth, height * aspectRatio), height: height)
    }

    private var controls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Button {
                    previewModel.setKeepsAspectRatio(!previewModel.keepsAspectRatio)
                } label: {
                    Image(systemName: previewModel.keepsAspectRatio ? "lock.fill" : "lock.open")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                .accessibilityLabel(previewModel.keepsAspectRatio ? "Unlock aspect ratio" : "Lock aspect ratio")

                Text("Original")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("\(Int(previewModel.pixelSize.width)) x \(Int(previewModel.pixelSize.height)) px · \(previewModel.formattedInputSize)")
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
                    get: { previewModel.unit },
                    set: { previewModel.applyUnit($0) }
                )) {
                    ForEach(ImageDimensionUnit.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 58)
            }

            if enabledOptions.contains(.width) {
                VideoTransformDimensionControl(
                    title: "Width",
                    value: Binding(get: { previewModel.width }, set: { previewModel.setWidth($0) }),
                    unit: previewModel.unit,
                    range: previewModel.range(for: .horizontal)
                )
            }
            if enabledOptions.contains(.height) {
                VideoTransformDimensionControl(
                    title: "Height",
                    value: Binding(get: { previewModel.height }, set: { previewModel.setHeight($0) }),
                    unit: previewModel.unit,
                    range: previewModel.range(for: .vertical)
                )
            }

            if enabledOptions.contains(.fps) {
                valueControl(title: "FPS", value: $model.fps, range: 1...120, suffix: "")
            }
            if enabledOptions.contains(.bitrate) {
                valueControl(title: "Bitrate", value: $model.bitrateKbps, range: 100...50_000, suffix: "kbps")
            }
            if enabledOptions.contains(.quality) {
                valueControl(title: "Quality", value: $model.quality, range: 1...100, suffix: "%")
            }

            if enabledOptions.contains(.muteAudio) || enabledOptions.contains(.removeMetadata) {
                HStack(spacing: 14) {
                    if enabledOptions.contains(.muteAudio) {
                        Toggle("Mute audio", isOn: $model.mutesAudio)
                    }
                    if enabledOptions.contains(.removeMetadata) {
                        Toggle("Remove metadata", isOn: $model.removesMetadata)
                    }
                    Spacer(minLength: 0)
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 10, weight: .medium))
            }
        }
    }

    private func valueControl(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 42, alignment: .leading)
            ActionSlider(value: value, range: range)
            TextField("", value: value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
            Text(suffix).frame(width: 30, alignment: .leading)
        }
        .font(.system(size: 10, weight: .medium))
    }

}

#if DEBUG
#Preview("Video Compress") {
    VideoCompressView(
        model: VideoCompressModel(inputURL: URL(fileURLWithPath: "/tmp/missing.mp4")),
        fileCount: 1,
        enabledOptions: Set(VideoCompressOption.allCases),
        close: {},
        apply: { _ in }
    )
    .frame(width: VideoCompressView.width)
    .background(.regularMaterial)
}
#endif
