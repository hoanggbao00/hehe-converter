import AVFoundation
import AppKit
import SwiftUI

struct VideoTrimView: View {
    static let previewHeight: CGFloat = 220
    static let horizontalPadding: CGFloat = 14

    static func panelWidth(for pixelSize: CGSize) -> CGFloat {
        let aspectRatio = pixelSize.width > 0 && pixelSize.height > 0 ? pixelSize.width / pixelSize.height : 16 / 9
        return ceil(max(previewHeight * 4 / 3, previewHeight * aspectRatio) + horizontalPadding * 2)
    }

    @ObservedObject var model: VideoTrimModel
    let close: () -> Void
    let apply: () -> Void

    var body: some View {
        OverlayPanelView(title: "Video Trim", close: close, actions: []) {
            VStack(spacing: 0) {
                VideoTrimPreview(model: model)
                    .frame(width: previewWidth, height: Self.previewHeight)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 12)

                VideoTrimTimeline(model: model)
                    .frame(width: previewWidth, height: 46)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 8)

                VideoTrimTimeControls(model: model)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 6)

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

private struct VideoTrimTimeControls: View {
    @ObservedObject var model: VideoTrimModel
    @State private var draftStartTime = 0.0
    @State private var draftEndTime = 0.0

    var body: some View {
        HStack(spacing: 6) {
            Text("Start")
                .foregroundStyle(.secondary)
            timeField(value: $draftStartTime, label: "Start")
                .onSubmit { commitStart() }
            Spacer(minLength: 4)
            Text(model.formattedSelectionDuration)
                .foregroundStyle(.secondary)
            Button("Reset") {
                model.reset()
                syncDrafts()
            }
            .controlSize(.mini)
            Spacer(minLength: 4)
            Text("End")
                .foregroundStyle(.secondary)
            timeField(value: $draftEndTime, label: "End")
                .onSubmit { commitEnd() }
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .onAppear { syncDrafts() }
        .onReceive(model.$startTime) { draftStartTime = $0 }
        .onReceive(model.$endTime) { draftEndTime = $0 }
    }

    private func timeField(value: Binding<Double>, label: String) -> some View {
        HStack(spacing: 2) {
            TextField(label, value: value, format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
            Text("s")
                .foregroundStyle(.secondary)
        }
    }

    private func commitStart() {
        model.setStartTime(draftStartTime)
        syncDrafts()
    }

    private func commitEnd() {
        model.setEndTime(draftEndTime)
        syncDrafts()
    }

    private func syncDrafts() {
        draftStartTime = model.startTime
        draftEndTime = model.endTime
    }
}

private struct VideoTrimPreview: View {
    @ObservedObject var model: VideoTrimModel

    var body: some View {
        GeometryReader { geometry in
            let rect = fittedRect(for: model.pixelSize, in: geometry.size)
            ZStack {
                VideoTrimPlayerView(player: model.player)
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

private struct VideoTrimTimeline: View {
    @ObservedObject var model: VideoTrimModel
    @State private var draggedStartTime: Double?
    @State private var draggedEndTime: Double?

    var body: some View {
        HStack(spacing: 8) {
            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

            GeometryReader { geometry in
                let handleWidth: CGFloat = 12
                let timelineWidth = max(geometry.size.width - handleWidth * 2, 1)
                let timelineStart = handleWidth
                let timelineEnd = timelineStart + timelineWidth
                let startX = timelineStart + fraction(model.startTime) * timelineWidth
                let endX = timelineStart + fraction(model.endTime) * timelineWidth
                let playheadX = timelineStart + fraction(model.currentTime) * timelineWidth
                ZStack(alignment: .topLeading) {
                    VideoTrimFilmstrip(thumbnails: model.thumbnails)
                        .frame(width: timelineWidth, height: geometry.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.black.opacity(0.24), lineWidth: 1))
                        .offset(x: timelineStart)

                    Color.black.opacity(0.42)
                        .frame(width: max(0, startX - timelineStart), height: geometry.size.height)
                        .offset(x: timelineStart)
                    Color.black.opacity(0.42)
                        .frame(width: max(0, timelineEnd - endX), height: geometry.size.height)
                        .offset(x: endX)

                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.accentColor, lineWidth: 4)
                        .frame(width: max(0, endX - startX), height: geometry.size.height)
                        .offset(x: startX)

                    Rectangle()
                        .fill(.white)
                        .frame(width: 2, height: geometry.size.height)
                        .offset(x: min(max(playheadX - 1, timelineStart), timelineEnd - 2))
                        .opacity(model.currentTime >= model.startTime && model.currentTime <= model.endTime ? 0.9 : 0)

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            model.setCurrentTime(time(at: value.location.x - timelineStart, width: timelineWidth))
                        })

                    trimHandle(side: .left, centerX: startX - handleWidth / 2, systemImage: "chevron.left")
                        .highPriorityGesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let initialTime = draggedStartTime ?? model.startTime
                                draggedStartTime = initialTime
                                model.setStartTime(initialTime + timeOffset(for: value.translation.width, width: timelineWidth))
                            }
                            .onEnded { _ in draggedStartTime = nil })
                    trimHandle(side: .right, centerX: endX + handleWidth / 2, systemImage: "chevron.right")
                        .highPriorityGesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let initialTime = draggedEndTime ?? model.endTime
                                draggedEndTime = initialTime
                                model.setEndTime(initialTime + timeOffset(for: value.translation.width, width: timelineWidth))
                            }
                            .onEnded { _ in draggedEndTime = nil })
                }
            }
        }
    }

    private func fraction(_ time: Double) -> CGFloat {
        guard model.duration > 0 else { return 0 }
        return CGFloat(min(max(time / model.duration, 0), 1))
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        Double(min(max(x / max(width, 1), 0), 1)) * model.duration
    }

    private func timeOffset(for translation: CGFloat, width: CGFloat) -> Double {
        Double(translation / max(width, 1)) * model.duration
    }

    private func trimHandle(side: VideoTrimHandleSide, centerX: CGFloat, systemImage: String) -> some View {
        VideoTrimHandleShape(side: side)
            .fill(Color.accentColor)
            .frame(width: 12, height: 46)
            .overlay(Image(systemName: systemImage).font(.system(size: 7, weight: .bold)).foregroundStyle(.white))
            .contentShape(Rectangle())
            .position(x: centerX, y: 23)
    }
}

private enum VideoTrimHandleSide {
    case left
    case right
}

private struct VideoTrimHandleShape: Shape {
    let side: VideoTrimHandleSide

    func path(in rect: CGRect) -> Path {
        let radius = min(3, rect.width / 2, rect.height / 2)
        var path = Path()

        if side == .left {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + radius), control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }
}

private struct VideoTrimFilmstrip: View {
    let thumbnails: [NSImage]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if thumbnails.isEmpty {
                    Rectangle().fill(.black.opacity(0.18))
                } else {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width / CGFloat(thumbnails.count), height: geometry.size.height)
                            .clipped()
                    }
                }
            }
        }
    }
}

private struct VideoTrimPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> VideoTrimPlayerNSView {
        let view = VideoTrimPlayerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: VideoTrimPlayerNSView, context: Context) {
        view.playerLayer.player = player
    }
}

private final class VideoTrimPlayerNSView: NSView {
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
#Preview("Video Trim") {
    VideoTrimView(model: VideoTrimModel(inputURL: URL(fileURLWithPath: "/tmp/missing.mp4"))) {} apply: {}
        .frame(width: VideoTrimView.panelWidth(for: CGSize(width: 1920, height: 1080)))
        .background(.regularMaterial)
}
#endif
