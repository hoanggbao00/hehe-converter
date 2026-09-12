import AppKit
import SwiftUI

@MainActor
final class VideoActionPlaceholderWindowController {
    private let panel = OverlayPanelController()

    func show(action: VideoAction, near mouseLocation: NSPoint) {
        panel.show(
            size: NSSize(width: 320, height: 170),
            near: mouseLocation,
            content: VideoActionPlaceholderView(action: action) { [weak self] in
                self?.panel.hide()
            }
        )
    }
}

private struct VideoActionPlaceholderView: View {
    let action: VideoAction
    let close: () -> Void

    var body: some View {
        OverlayPanelView(title: "\(action.rawValue) Video", close: close, actions: []) {
            VStack(spacing: 10) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Coming soon")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
