import AppKit
import SwiftUI

@MainActor
final class VideoSnapshotWindowController {
    private let panel = OverlayPanelController()

    func show(inputURL: URL, near mouseLocation: NSPoint) {
        let model = VideoSnapshotModel(inputURL: inputURL)
        Task { [weak self] in
            guard let self else { return }
            await model.load()
            panel.show(
                width: VideoSnapshotView.panelWidth(for: model.pixelSize),
                near: mouseLocation,
                content: VideoSnapshotView(model: model) { [weak self] in
                    self?.hide()
                } apply: {
                    do {
                        return try await model.applySnapshot()
                    } catch {
                        model.errorMessage = error.localizedDescription
                        return nil
                    }
                } reveal: { outputURL in
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
            )
        }
    }

    func hide() {
        panel.hide()
    }
}
