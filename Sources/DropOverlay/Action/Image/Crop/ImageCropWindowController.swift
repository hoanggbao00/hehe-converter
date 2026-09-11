import AppKit
import SwiftUI

@MainActor
final class ImageCropWindowController {
    private let panel = OverlayPanelController()

    func show(inputURL: URL, near mouseLocation: NSPoint) {
        let model = ImageCropModel(inputURL: inputURL)
        let size = NSSize(width: 360, height: 470)
        panel.show(
            size: size,
            near: mouseLocation,
            content: ImageCropView(model: model) { [weak self] in
                self?.hide()
            } apply: { [weak self, weak model] in
                guard let model else { return }
                do {
                    let outputURL = try await model.applyCrop()
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    self?.hide()
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
            .frame(width: size.width, height: size.height)
        )
    }

    func hide() {
        panel.hide()
    }
}
