import AppKit
import SwiftUI

@MainActor
final class VideoTrimWindowController {
    private let panel = OverlayPanelController()

    func show(inputURL: URL, near mouseLocation: NSPoint, apply: @escaping (Double, Double) -> Void) {
        let model = VideoTrimModel(inputURL: inputURL)
        Task { [weak self] in
            guard let self else { return }
            await model.load()
            panel.show(
                width: VideoTrimView.panelWidth(for: model.pixelSize),
                near: mouseLocation,
                content: VideoTrimView(model: model) { [weak self] in
                    self?.hide()
                } apply: {
                    model.player.pause()
                    apply(model.startTime, model.endTime)
                    self.hide()
                }
            )
        }
    }

    func hide() {
        panel.hide()
    }
}
