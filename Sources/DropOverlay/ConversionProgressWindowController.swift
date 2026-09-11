import AppKit
import SwiftUI

@MainActor
final class ConversionProgressWindowController {
    private let panel: NSPanel
    private let model = ConversionProgressModel()
    var onCancel: (() -> Void)?
    var onDismiss: (() -> Void)?

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func show(title: String, near mouseLocation: NSPoint) {
        model.title = title
        model.subtitle = "Preparing"
        model.progress = 0
        model.isIndeterminate = false
        model.isFinished = false

        let contentWidth: CGFloat = 300
        let hostingView = TransparentHostingView(
            rootView: ConversionProgressView(model: model) { [weak self] in
                self?.cancel()
            }
            .frame(width: contentWidth)
            .fixedSize(horizontal: false, vertical: true)
        )
        let contentSize = NSSize(
            width: contentWidth,
            height: max(hostingView.fittingSize.height, 88)
        )
        panel.setFrame(
            NSRect(
                x: mouseLocation.x - contentSize.width / 2,
                y: mouseLocation.y + 16,
                width: contentSize.width,
                height: contentSize.height
            ),
            display: false
        )
        hostingView.frame = NSRect(origin: .zero, size: contentSize)
        let container = RoundedMaterialView(cornerRadius: 12)
        container.frame = NSRect(origin: .zero, size: contentSize)
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container
        panel.orderFrontRegardless()
    }

    func update(_ update: ImagePresetConversionUpdate) {
        switch update.state {
        case .running:
            model.subtitle = update.subtitle
            model.progress = update.progress
            model.isIndeterminate = update.isIndeterminate
        case .finished:
            model.subtitle = update.subtitle
            model.progress = 1
            model.isIndeterminate = false
            model.isFinished = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.hide()
            }
        case .failed:
            model.subtitle = update.subtitle
            model.isIndeterminate = false
            model.isFinished = true
        }
    }

    func hide() {
        panel.orderOut(nil)
        onDismiss?()
        onCancel = nil
        onDismiss = nil
    }

    private func cancel() {
        onCancel?()
        hide()
    }
}

@MainActor
private final class ConversionProgressModel: ObservableObject {
    @Published var title = "Converting"
    @Published var subtitle = "Preparing"
    @Published var progress = 0.0
    @Published var isIndeterminate = false
    @Published var isFinished = false
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }
    override var wantsDefaultClipping: Bool { false }
}

private final class RoundedMaterialView: NSVisualEffectView {
    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct ConversionProgressView: View {
    @ObservedObject var model: ConversionProgressModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                CloseProgressButton(action: close)

                Text(model.title)
                    .font(.headline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(model.subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            AccentProgressBar(value: model.progress, isIndeterminate: model.isIndeterminate)
                .frame(height: 5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

private struct CloseProgressButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption2.bold())
                .foregroundStyle(isHovering ? .white : .black.opacity(0.50))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.red : Color.black.opacity(0.09), in: Circle())
        .accessibilityLabel("Close")
        .onHover { isHovering = $0 }
    }
}

struct AccentProgressBar: View {
    let value: Double
    let isIndeterminate: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clampedValue = min(max(value, 0), 1)
            Capsule()
                .fill(Color.white.opacity(0.72))
                .overlay(alignment: .leading) {
                    if isIndeterminate {
                        TimelineView(.animation) { timeline in
                            let time = timeline.date.timeIntervalSinceReferenceDate
                            let thumbWidth = Self.indeterminateWidth(at: time, trackWidth: width)
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: thumbWidth)
                                .offset(x: Self.indeterminateOffset(
                                    at: time,
                                    travel: max(width - thumbWidth, 0)
                                ))
                        }
                    } else {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: width * clampedValue)
                    }
                }
                .clipShape(Capsule())
        }
    }

    nonisolated static func indeterminateOffset(at time: TimeInterval, travel: CGFloat) -> CGFloat {
        travel * indeterminateTravel(at: time)
    }

    nonisolated static func indeterminateWidth(at time: TimeInterval, trackWidth: CGFloat) -> CGFloat {
        let distanceFromEdge = sin(indeterminateTravel(at: time) * .pi)
        return max(trackWidth * (0.16 + distanceFromEdge * 0.24), 24)
    }

    nonisolated private static func indeterminateTravel(at time: TimeInterval) -> CGFloat {
        let phase = time.truncatingRemainder(dividingBy: 1.6) / 1.6
        return CGFloat(1 - abs(phase * 2 - 1))
    }
}
