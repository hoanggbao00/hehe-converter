import AppKit
import SwiftUI

@MainActor
final class VideoCompressWindowController {
    private let panel = OverlayPanelController()

    func show(
        inputURLs: [URL],
        near mouseLocation: NSPoint,
        apply: @escaping (VideoCompressSettings) -> Void
    ) {
        guard let inputURL = inputURLs.first else { return }
        let model = VideoCompressModel(inputURL: inputURL)
        panel.show(
            width: VideoCompressView.width,
            near: mouseLocation,
            content: VideoCompressView(
                model: model,
                fileCount: inputURLs.count,
                close: { [weak self] in self?.hide() },
                apply: { [weak self] settings in
                    self?.hide()
                    apply(settings)
                }
            )
        )
    }

    func hide() {
        panel.hide()
    }
}
