import AppKit
import SwiftUI

@MainActor
final class ConversionProgressWindowController {
    private let panel: NSPanel
    private let model = ConversionProgressModel()
    var onCancel: (() -> Void)?
    var onCancelItem: ((UUID) -> Void)?
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
        model.items = []
        model.isFinished = false

        let contentWidth: CGFloat = 360
        let hostingView = TransparentHostingView(
            rootView: ConversionProgressView(model: model, cancelItem: { [weak self] id in
                self?.onCancelItem?(id)
            }) { [weak self] in
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
            model.items = update.items
        case .finished:
            model.subtitle = update.subtitle
            model.isFinished = true
            model.items = update.items
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.hide()
            }
        case .failed:
            model.subtitle = update.subtitle
            model.isFinished = true
            model.items = update.items
        }
        resizeToFit()
    }

    func hide() {
        panel.orderOut(nil)
        onDismiss?()
        onCancel = nil
        onCancelItem = nil
        onDismiss = nil
    }

    private func cancel() {
        onCancel?()
        hide()
    }

    private func resizeToFit() {
        guard let contentView = panel.contentView,
              let hostingView = contentView.subviews.first else { return }
        let fittingSize = hostingView.fittingSize
        let height = max(fittingSize.height, 88)
        guard abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
        contentView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.frame = contentView.bounds
    }
}

@MainActor
private final class ConversionProgressModel: ObservableObject {
    @Published var title = "Converting"
    @Published var subtitle = "Preparing"
    @Published var isFinished = false
    @Published var items: [ConversionProgressItem] = []
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
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
        alphaValue = 0.94
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
    let cancelItem: (UUID) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            VStack(spacing: 9) {
                ForEach(model.items) { item in
                    ConversionProgressRow(item: item) {
                        cancelItem(item.id)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

private struct ConversionProgressRow: View {
    let item: ConversionProgressItem
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.status.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.status.color)
                .frame(width: 14)

            Text(item.filename)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 92, maxWidth: .infinity, alignment: .leading)

            AccentProgressBar(value: item.progress, isIndeterminate: item.isIndeterminate)
                .frame(width: 112, height: 5)

            CancelProgressItemButton(action: cancel)
            .disabled(item.status.isComplete)
            .opacity(item.status.isComplete ? 0.35 : 1)
            .accessibilityLabel("Cancel \(item.filename)")
        }
    }
}

private struct CancelProgressItemButton: View {
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption2.bold())
                .foregroundStyle(isHovering && isEnabled ? .white : .secondary)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .background(isHovering && isEnabled ? Color.red : Color.black.opacity(0.09), in: Circle())
        .onHover { isHovering = $0 }
    }
}

private extension ConversionProgressItem.Status {
    var systemImage: String {
        switch self {
        case .pending: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .saved: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .canceled: "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .saved: .green
        case .failed: .red
        default: .secondary
        }
    }

    var isComplete: Bool {
        switch self {
        case .saved, .failed, .canceled: true
        case .pending, .running: false
        }
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
