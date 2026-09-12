import AppKit
import SwiftUI

@MainActor
final class ImageCropWindowController {
    private let panel = OverlayPanelController()

    func show(inputURLs: [URL], near mouseLocation: NSPoint) {
        let models = inputURLs.map(ImageCropModel.init(inputURL:))
        guard !models.isEmpty else { return }
        let width = models.count == 1
            ? ImageCropView.singleWidth
            : ImageCropView.multiColumnWidth * CGFloat(min(models.count, 3))
        let size = NSSize(width: width, height: ImageCropView.panelHeight)
        panel.show(
            size: size,
            near: mouseLocation,
            content: ImageCropView(models: models) { [weak self] in
                self?.hide()
            } apply: { model in
                do {
                    return try await model.applyCrop()
                } catch {
                    model.errorMessage = error.localizedDescription
                    return nil
                }
            } reveal: { outputURL in
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            }
            .frame(width: size.width, height: size.height)
        )
    }

    func hide() {
        panel.hide()
    }
}
