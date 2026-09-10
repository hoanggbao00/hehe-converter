import AppKit
import SwiftUI

@MainActor
final class ConversionProgressWindowController: NSObject {
    private var window: NSWindow?
    private var alert: NSAlert?
    private let model = ConversionProgressModel()

    override init() {}

    func show(title: String, near mouseLocation: NSPoint) {
        model.title = title
        model.subtitle = "Preparing"
        model.progress = 0
        model.isFinished = false

        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "Hide")
        alert.accessoryView = NSHostingView(
            rootView: NativeProgressAccessory(model: model)
                .frame(width: 260, height: 42)
        )
        alert.buttons.first?.target = self
        alert.buttons.first?.action = #selector(hideFromButton)

        let window = alert.window
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.alert = alert
        self.window = window
        window.center()
        window.orderFrontRegardless()
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
        window?.close()
        window = nil
        alert = nil
    }

    @objc private func hideFromButton() {
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

private struct NativeProgressAccessory: View {
    @ObservedObject var model: ConversionProgressModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if model.isIndeterminate {
                ProgressView()
                    .progressViewStyle(.linear)
            } else {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
            }
        }
    }
}
