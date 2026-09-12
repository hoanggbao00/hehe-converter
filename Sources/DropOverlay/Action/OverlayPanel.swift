import AppKit
import SwiftUI

enum OverlayPanelActionVariant {
    case primary
    case secondary
    case destructive
}

struct OverlayPanelAction: Identifiable {
    let label: String
    let action: () -> Void
    let variant: OverlayPanelActionVariant
    var isEnabled = true

    var id: String { label }
}

struct OverlayPanelView<Content: View>: View {
    let title: String
    let close: () -> Void
    let actions: [OverlayPanelAction]
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            OverlayPanelHeader(title: title, close: close)
            Divider().opacity(0.36)
            content
            if !actions.isEmpty {
                Divider().opacity(0.36)
                OverlayPanelActions(actions: actions)
            }
        }
    }
}

@MainActor
final class OverlayPanelController {
    private let panel: OverlayPanel
    private weak var clipView: NSView?

    init(level: NSWindow.Level = .popUpMenu, cornerRadius: CGFloat = 18) {
        panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.cornerRadius = cornerRadius
    }

    private let cornerRadius: CGFloat

    func show<Content: View>(size: NSSize, near mouseLocation: NSPoint, content: Content) {
        let origin = constrainedOrigin(
            for: size,
            preferred: NSPoint(
                x: mouseLocation.x - size.width / 2,
                y: mouseLocation.y - size.height / 2
            ),
            near: mouseLocation
        )
        panel.setFrame(
            NSRect(
                x: origin.x,
                y: origin.y,
                width: size.width,
                height: size.height
            ),
            display: false
        )

        let hostingView = OverlayPanelHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let rootView = NSView(frame: NSRect(origin: .zero, size: size))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor

        let clipView = NSView(frame: NSRect(origin: .zero, size: size))
        clipView.wantsLayer = true
        clipView.layer?.cornerRadius = cornerRadius
        clipView.layer?.cornerCurve = .continuous
        clipView.layer?.masksToBounds = true

        let container = OverlayPanelMaterialView(cornerRadius: 0)
        container.frame = NSRect(origin: .zero, size: size)
        container.autoresizingMask = [.width, .height]
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        clipView.addSubview(container)
        rootView.addSubview(clipView)
        panel.contentView = rootView
        self.clipView = clipView
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func constrainedOrigin(for size: NSSize, preferred: NSPoint, near point: NSPoint) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else {
            return preferred
        }
        let visibleFrame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        return NSPoint(
            x: min(max(preferred.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - size.width)),
            y: min(max(preferred.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - size.height))
        )
    }

    func hide() {
        panel.orderOut(nil)
        panel.contentView = nil
        clipView = nil
    }

    func animateWidth(to width: CGFloat, duration: TimeInterval) {
        guard panel.frame.width != width else { return }
        guard let clipView else { return }
        if width > panel.frame.width {
            var frame = panel.frame
            frame.size.width = width
            panel.setFrame(frame, display: false)
        }
        var clipFrame = clipView.frame
        clipFrame.size.width = width
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            clipView.animator().frame = clipFrame
        } completionHandler: { [weak panel] in
            Task { @MainActor in
                guard let panel else { return }
                var frame = panel.frame
                frame.size.width = width
                panel.setFrame(frame, display: false)
            }
        }
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct OverlayPanelHeader: View {
    let title: String
    let close: () -> Void
    @State private var isCloseHovering = false

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(isCloseHovering ? .white : .primary)
                        .frame(width: 18, height: 18)
                        .background(isCloseHovering ? Color.red : Color.black.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .onHover { isCloseHovering = $0 }
                .accessibilityLabel("Close")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background {
            OverlayPanelDragHandle()
        }
    }
}

private struct OverlayPanelActions: View {
    let actions: [OverlayPanelAction]

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            ForEach(actions) { action in
                OverlayPanelActionButton(action: action)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }
}

private struct OverlayPanelActionButton: View {
    let action: OverlayPanelAction

    var body: some View {
        Button(action: action.action) {
            Text(action.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(foregroundStyle)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
    }

    private var foregroundStyle: Color {
        switch action.variant {
        case .primary, .destructive: .white
        case .secondary: .primary
        }
    }

    private var backgroundStyle: Color {
        switch action.variant {
        case .primary: Color(nsColor: .controlAccentColor)
        case .secondary: Color.black.opacity(0.06)
        case .destructive: .red
        }
    }
}

struct OverlayPanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        OverlayPanelDragHandleNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class OverlayPanelDragHandleNSView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class OverlayPanelHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }
}

private final class OverlayPanelMaterialView: NSVisualEffectView {
    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
        alphaValue = 0.98
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
