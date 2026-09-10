import AppKit
import SwiftUI

@MainActor
final class ConversionProgressWindowController {
    private let panel: NSPanel
    private let model = ConversionProgressModel()

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
        model.isFinished = false

        let size = NSSize(width: 260, height: 82)
        panel.setFrame(
            NSRect(
                x: mouseLocation.x - size.width / 2,
                y: mouseLocation.y + 16,
                width: size.width,
                height: size.height
            ),
            display: false
        )
        let hostingView = TransparentHostingView(
            rootView: ConversionProgressView(model: model) { [weak self] in
                self?.hide()
            }
            .frame(width: size.width, height: size.height)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        let container = RoundedMaterialView(cornerRadius: 16)
        container.frame = NSRect(origin: .zero, size: size)
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
        material = .hudWindow
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
            HStack(spacing: 8) {
                Button(action: close) {
                    Text("x")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.42))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .background(Color.black.opacity(0.07), in: Circle())

                Text(model.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }

            Text(model.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            AccentProgressBar(
                value: model.progress,
                isIndeterminate: model.isIndeterminate
            )
            .frame(height: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

private struct AccentProgressBar: View {
    let value: Double
    let isIndeterminate: Bool
    @State private var indeterminateOffset = -0.35

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clampedValue = min(max(value, 0), 1)
            Capsule()
                .fill(Color.white.opacity(0.72))
                .overlay(alignment: .leading) {
                    if isIndeterminate {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(width * 0.28, 24))
                            .offset(x: width * indeterminateOffset)
                    } else {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: width * clampedValue)
                    }
                }
                .clipShape(Capsule())
                .onAppear(perform: updateAnimation)
                .onChange(of: isIndeterminate) { _ in updateAnimation() }
        }
    }

    private func updateAnimation() {
        guard isIndeterminate else { return }
        indeterminateOffset = -0.35
        withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
            indeterminateOffset = 1.05
        }
    }
}
