import AppKit
import SwiftUI

@MainActor
final class ImageResizeWindowController {
    private let panel = OverlayPanelController()

    func show(inputURLs: [URL], near mouseLocation: NSPoint) {
        let models = inputURLs.map(ImageResizeModel.init(inputURL:))
        guard !models.isEmpty else { return }
        let width = models.count == 1
            ? ImageResizeView.singleWidth
            : ImageResizeView.multiColumnWidth * CGFloat(min(models.count, 3))
        let size = NSSize(width: width, height: ImageResizeView.panelHeight)
        panel.show(
            size: size,
            near: mouseLocation,
            content: ImageResizeView(models: models) { [weak self] in
                self?.hide()
            } apply: { model in
                do {
                    return try await model.applyResize()
                } catch {
                    model.errorMessage = error.localizedDescription
                    return nil
                }
            } reveal: { outputURL in
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } resizeWindow: { [weak self] width, duration in
                self?.panel.animateWidth(to: width, duration: duration)
            }
            .frame(height: size.height)
        )
    }

    func hide() {
        panel.hide()
    }
}
