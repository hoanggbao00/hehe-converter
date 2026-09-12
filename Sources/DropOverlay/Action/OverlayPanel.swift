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
        panel.setFrame(
            NSRect(
                x: mouseLocation.x - size.width / 2,
                y: mouseLocation.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: false
        )

        let hostingView = OverlayPanelHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let container = OverlayPanelMaterialView(cornerRadius: cornerRadius)
        container.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
        panel.contentView = nil
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
