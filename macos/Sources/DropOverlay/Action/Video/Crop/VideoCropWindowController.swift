import AppKit
import SwiftUI

@MainActor
final class VideoCropWindowController {
    private let panel = OverlayPanelController()
    private var pendingURLs: [URL] = []
    private var mouseLocation = NSPoint.zero

    func show(inputURLs: [URL], near mouseLocation: NSPoint) {
        pendingURLs = inputURLs
        self.mouseLocation = mouseLocation
        showNext()
    }

    private func showNext() {
        guard let inputURL = pendingURLs.first else {
            hide()
            return
        }
        pendingURLs.removeFirst()
        let model = VideoCropModel(inputURL: inputURL)
        Task { [weak self] in
            guard let self else { return }
            await model.load()
            let width = VideoCropView.panelWidth(for: model.pixelSize)
            panel.show(width: width, near: mouseLocation, content: VideoCropView(model: model) { [weak self] in
                self?.hide()
            } apply: {
                do {
                    return try await model.applyCrop()
                } catch {
                    model.errorMessage = error.localizedDescription
                    return nil
                }
            } reveal: { outputURL in
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } complete: { [weak self] in
                self?.showNext()
            })
        }
    }

    func hide() {
        pendingURLs = []
        panel.hide()
    }
}
