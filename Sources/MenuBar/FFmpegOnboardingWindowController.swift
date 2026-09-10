import AppKit
import SwiftUI

@MainActor
final class FFmpegOnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let ffmpeg = FFmpegInstallStore()

    init() {
        let window = NSWindow()
        super.init(window: window)

        window.title = "Setup"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: FFmpegOnboardingView(ffmpeg: ffmpeg) { [weak window] in
                window?.close()
            }
        )
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !ffmpeg.isDownloading
    }
}
