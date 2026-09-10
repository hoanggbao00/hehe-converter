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
        panel.contentViewController = NSHostingController(
            rootView: ConversionProgressView(model: model) { [weak self] in
                self?.hide()
            }
            .frame(width: size.width, height: size.height)
        )
        panel.orderFrontRegardless()
    }

    func update(_ update: ImagePresetConversionUpdate) {
        switch update.state {
        case .running:
            model.subtitle = update.subtitle
            model.progress = update.progress
        case .finished:
            model.subtitle = update.subtitle
            model.progress = 1
            model.isFinished = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.hide()
            }
        case .failed:
            model.subtitle = update.subtitle
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
    @Published var isFinished = false
}

private struct ConversionProgressView: View {
    @ObservedObject var model: ConversionProgressModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.42))

                    Capsule()
                        .fill(Color.accentColor.opacity(0.9))
                        .frame(width: max(0, proxy.size.width * model.progress))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}
