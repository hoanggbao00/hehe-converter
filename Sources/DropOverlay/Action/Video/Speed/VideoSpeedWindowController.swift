import AppKit
import SwiftUI

@MainActor
final class VideoSpeedWindowController {
    private let panel = OverlayPanelController()

    func show(inputURL: URL, near mouseLocation: NSPoint, apply: @escaping (Double, Bool) -> Void) {
        let model = VideoSpeedModel(inputURL: inputURL)
        Task { [weak self] in
            guard let self else { return }
            await model.load()
            panel.show(
                width: VideoSpeedView.panelWidth(for: model.pixelSize),
                near: mouseLocation,
                content: VideoSpeedView(model: model) { [weak self] in
                    self?.hide()
                } apply: {
                    model.player.pause()
                    apply(model.speed, model.muteAudio)
                    self.hide()
                }
            )
        }
    }

    func hide() {
        panel.hide()
    }
}
