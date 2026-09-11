import AppKit
import SwiftUI

@MainActor
final class PresetOverlayWindowController {
    private let panel: NSPanel
    private let model = PresetBloomModel()
    private var signature: String?
    private var dropHandler: (() -> Void)?

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
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func show(presets: [DropPreset], fileURLs: [URL], near mouseLocation: NSPoint, onDrop: @escaping () -> Void) {
        let newSignature = fileURLs.map(\.path).joined() + presets.map(\.id.uuidString).joined()
        dropHandler = onDrop
        guard signature != newSignature || !panel.isVisible else { return }
        signature = newSignature
        model.presets = presets
        model.selectedIndex = nil

        let size = NSSize(width: 300, height: 300)
        let origin = constrainedOrigin(
            for: size,
            preferred: NSPoint(
                x: mouseLocation.x - size.width / 2,
                y: mouseLocation.y - size.height / 2
            )
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.contentView = PresetDropShieldHostingView(
            rootView: PresetBloomView(model: model)
                .frame(width: size.width, height: size.height),
            onDrop: { [weak self] in self?.dropHandler?() }
        )
        panel.orderFrontRegardless()
    }

    func updateSelection(at screenPoint: NSPoint) {
        guard panel.isVisible else { return }
        let localX = screenPoint.x - panel.frame.minX
        let localY = screenPoint.y - panel.frame.minY
        let deltaX = localX - panel.frame.width / 2
        let deltaY = localY - panel.frame.height / 2
        model.selectedIndex = PresetBloomGeometry(
            count: model.presets.count,
            innerRadius: 43,
            outerRadius: 112
        ).selectedIndex(deltaX: deltaX, deltaY: deltaY)
    }

    func selectedPreset() -> DropPreset? {
        guard let selectedIndex = model.selectedIndex,
              model.presets.indices.contains(selectedIndex) else { return nil }
        return model.presets[selectedIndex]
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func hide() {
        panel.orderOut(nil)
        signature = nil
        model.selectedIndex = nil
        dropHandler = nil
    }

    private func constrainedOrigin(for size: NSSize, preferred: NSPoint) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main else { return preferred }
        let frame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        return NSPoint(
            x: min(max(preferred.x, frame.minX), frame.maxX - size.width),
            y: min(max(preferred.y, frame.minY), frame.maxY - size.height)
        )
    }
}

private final class PresetDropShieldHostingView<Content: View>: NSHostingView<Content> {
    private let onDrop: () -> Void

    init(rootView: Content, onDrop: @escaping () -> Void) {
        self.onDrop = onDrop
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("init(rootView:) has not been implemented")
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop()
        return true
    }
}

@MainActor
private final class PresetBloomModel: ObservableObject {
    @Published var presets: [DropPreset] = []
    @Published var selectedIndex: Int?
}

enum DropPreset: Identifiable, Equatable {
    case image(ImagePreset)
    case video(VideoPreset)
    case audio(VideoPreset)

    var id: UUID {
        switch self {
        case let .image(preset): preset.id
        case let .video(preset): preset.id
        case let .audio(preset): preset.id
        }
    }

    var name: String {
        switch self {
        case let .image(preset): preset.name
        case let .video(preset): preset.name
        case let .audio(preset): preset.name
        }
    }

    var outputLabel: String {
        switch self {
        case let .image(preset): preset.outputFormat.label
        case let .video(preset): preset.outputFormat.label
        case let .audio(preset): preset.outputFormat.label
        }
    }
}

private struct PresetBloomView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: PresetBloomModel
    @State private var isExpanded = false

    private var presets: [DropPreset] { model.presets }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.52 : 0.44))
                    .frame(width: 232, height: 232)
                    .position(center)
                    .opacity(isExpanded ? 1 : 0)
                    .allowsHitTesting(false)

                ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                    let isHovered = model.selectedIndex == index
                    PresetBloomPetal(
                        index: index,
                        count: presets.count,
                        isHovered: isHovered
                    )
                    .frame(width: 224, height: 224)
                    .position(center)
                    .scaleEffect(isExpanded ? 1 : 0.42)
                    .rotationEffect(isExpanded ? .zero : .degrees(-8))
                    .shadow(color: .black.opacity(isHovered ? 0.22 : 0.13), radius: 9, y: 3)
                    .animation(
                        .spring(response: 0.24, dampingFraction: 0.78)
                            .delay(Double(index) * 0.018),
                        value: isExpanded
                    )
                    .animation(.easeOut(duration: 0.12), value: isHovered)

                    Text(preset.name)
                        .font(.system(size: labelFontSize(count: presets.count), weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.82))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 72)
                        .position(labelPosition(for: index, center: center))
                        .opacity(isExpanded ? 1 : 0)
                        .animation(
                            .spring(response: 0.24, dampingFraction: 0.78)
                                .delay(Double(index) * 0.018),
                            value: isExpanded
                        )
                        .allowsHitTesting(false)
                }

                Circle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.18))
                    .frame(width: 86, height: 86)
                    .position(center)
                    .opacity(isExpanded ? 1 : 0)
                    .allowsHitTesting(false)

                if let selectedIndex = model.selectedIndex,
                   presets.indices.contains(selectedIndex) {
                    let selected = presets[selectedIndex]
                    Text(selected.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 18)
                        .frame(height: 28)
                        .background(.regularMaterial, in: Capsule())
                        .overlay { Capsule().stroke(.separator.opacity(0.5), lineWidth: 1) }
                        .position(center)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            isExpanded = true
        }
    }

    private func labelPosition(for index: Int, center: CGPoint) -> CGPoint {
        let angle = angle(for: index, count: presets.count)
        let radius = 77.0
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func angle(for index: Int, count: Int) -> Double {
        -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(max(count, 1))
    }

    private func labelFontSize(count: Int) -> CGFloat {
        let maxSize = 13.0
        let minSize = 9.0
        let size = maxSize - Double(max(count - 5, 0)) * 0.8
        return CGFloat(min(max(size, minSize), maxSize))
    }
}

private struct PresetBloomPetal: View {
    @Environment(\.colorScheme) private var colorScheme
    let index: Int
    let count: Int
    let isHovered: Bool

    var body: some View {
        let segment = PresetBloomSegment(index: index, count: count)
        segment
            .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.32) : Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.68 : 0.58))
            .contentShape(segment)
    }
}

private struct PresetBloomSegment: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let outerRadius = min(rect.width, rect.height) * 0.49
        let innerRadius = min(rect.width, rect.height) * 0.20
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let slot = 360.0 / Double(max(count, 1))
        let gap = 3.0
        let mid = -90.0 + Double(index) * slot
        let start = mid - slot / 2 + gap / 2
        let end = mid + slot / 2 - gap / 2
        let cornerRadius = 9.0
        let outerCornerAngle = cornerRadius / outerRadius * 180 / .pi
        let innerCornerAngle = cornerRadius / innerRadius * 180 / .pi

        var path = Path()
        path.move(to: point(center: center, radius: outerRadius, degrees: start + outerCornerAngle))
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(start + outerCornerAngle),
            endAngle: .degrees(end - outerCornerAngle),
            clockwise: false
        )
        path.addQuadCurve(
            to: point(center: center, radius: outerRadius - cornerRadius, degrees: end),
            control: point(center: center, radius: outerRadius, degrees: end)
        )
        path.addLine(to: point(center: center, radius: innerRadius + cornerRadius, degrees: end))
        path.addQuadCurve(
            to: point(center: center, radius: innerRadius, degrees: end - innerCornerAngle),
            control: point(center: center, radius: innerRadius, degrees: end)
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(end - innerCornerAngle),
            endAngle: .degrees(start + innerCornerAngle),
            clockwise: true
        )
        path.addQuadCurve(
            to: point(center: center, radius: innerRadius + cornerRadius, degrees: start),
            control: point(center: center, radius: innerRadius, degrees: start)
        )
        path.addLine(to: point(center: center, radius: outerRadius - cornerRadius, degrees: start))
        path.addQuadCurve(
            to: point(center: center, radius: outerRadius, degrees: start + outerCornerAngle),
            control: point(center: center, radius: outerRadius, degrees: start)
        )
        path.closeSubpath()
        return path
    }

    private func point(center: CGPoint, radius: Double, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }
}

#if DEBUG
#Preview("Preset Bloom") {
    PresetBloomView(model: PresetBloomModel.preview)
    .frame(width: 300, height: 300)
    .padding(32)
    .background(
        LinearGradient(
            colors: [.red, .yellow, .purple.opacity(0.6)],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    )
}

private extension PresetBloomModel {
    static var preview: PresetBloomModel {
        let model = PresetBloomModel()
        model.presets = [
            .image(ImagePreset(name: "WebP", outputFormat: .webp)),
            .image(ImagePreset(name: "JPG", outputFormat: .jpg)),
            .image(ImagePreset(name: "PNG", outputFormat: .png)),
            .image(ImagePreset(name: "AVIF", outputFormat: .avif)),
            .image(ImagePreset(name: "TIFF", outputFormat: .tiff)),
        ]
        model.selectedIndex = 0
        return model
    }
}
#endif
