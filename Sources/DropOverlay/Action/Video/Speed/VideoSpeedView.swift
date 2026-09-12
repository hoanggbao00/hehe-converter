import AVFoundation
import AppKit
import SwiftUI

struct VideoSpeedView: View {
    static let previewHeight: CGFloat = 240
    static let horizontalPadding: CGFloat = 14

    static func panelWidth(for pixelSize: CGSize) -> CGFloat {
        let aspectRatio = pixelSize.width > 0 && pixelSize.height > 0 ? pixelSize.width / pixelSize.height : 16 / 9
        return ceil(max(previewHeight * 4 / 3, previewHeight * aspectRatio) + horizontalPadding * 2)
    }

    @ObservedObject var model: VideoSpeedModel
    let close: () -> Void
    let apply: () -> Void

    var body: some View {
        OverlayPanelView(title: "Video Speed", close: close, actions: []) {
            VStack(spacing: 0) {
                VideoSpeedPreview(model: model)
                    .frame(width: previewWidth, height: Self.previewHeight)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 12)

                VideoSpeedPlaybackControls(model: model)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    Text("Speed")
                        .font(.system(size: 11, weight: .medium))
                    Slider(
                        value: $model.draftSpeed,
                        in: VideoSpeedModel.speedRange,
                        step: 0.05,
                        onEditingChanged: { editing in
                            if !editing { model.commitSpeed() }
                        }
                    )
                        .controlSize(.mini)
                        .accessibilityLabel("Playback speed")
                    TextField("Speed", value: $model.draftSpeed, format: .number.precision(.fractionLength(0...2)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 48)
                        .onSubmit { model.commitSpeed() }
                    Text("x")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.top, 12)

                Toggle("Mute audio", isOn: $model.muteAudio)
                    .font(.system(size: 11, weight: .medium))
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 8)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Self.horizontalPadding)
                        .padding(.top, 8)
                }

                Color.clear.frame(height: 8)
                Divider().opacity(0.36)
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.inputURL.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(Int(model.pixelSize.width)) x \(Int(model.pixelSize.height)) px · \(model.formattedInputSize)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10, weight: .medium))
                    Spacer(minLength: 8)
                    Button("Apply") { apply() }
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(model.isLoading || !model.canApply)
                }
                .padding(.horizontal, Self.horizontalPadding)
                .frame(height: 48)
            }
        }
        .task { await model.load() }
        .onDisappear { model.player.pause() }
    }

    private var previewWidth: CGFloat {
        Self.panelWidth(for: model.pixelSize) - Self.horizontalPadding * 2
    }
}

private struct VideoSpeedPreview: View {
    @ObservedObject var model: VideoSpeedModel

    var body: some View {
        GeometryReader { geometry in
            let rect = fittedRect(for: model.pixelSize, in: geometry.size)
            ZStack {
                VideoSpeedPlayerView(player: model.player)
                    .frame(width: rect.width, height: rect.height)
                    .background(.black, in: RoundedRectangle(cornerRadius: 4))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .position(x: rect.midX, y: rect.midY)
                if model.isLoading { ProgressView().controlSize(.small) }
            }
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

private struct VideoSpeedPlaybackControls: View {
    @ObservedObject var model: VideoSpeedModel

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

            Button("Reset") { model.resetSpeed() }
                .controlSize(.mini)
        }
    }
}

private struct VideoSpeedPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> VideoSpeedPlayerNSView {
        let view = VideoSpeedPlayerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: VideoSpeedPlayerNSView, context: Context) {
        view.playerLayer.player = player
    }
}

private final class VideoSpeedPlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer = playerLayer
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#if DEBUG
#Preview("Video Speed") {
    VideoSpeedView(model: VideoSpeedModel(inputURL: URL(fileURLWithPath: "/tmp/missing.mp4"))) {} apply: {}
        .frame(width: VideoSpeedView.panelWidth(for: CGSize(width: 1920, height: 1080)))
        .background(.regularMaterial)
}
#endif
