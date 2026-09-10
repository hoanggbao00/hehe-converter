import AppKit
import SwiftUI

struct OverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollerConfigurationView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ScrollerConfigurationView)?.configure()
    }
}

private final class ScrollerConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure()
    }

    func configure() {
        DispatchQueue.main.async {
            guard let root = self.window?.contentView else { return }
            self.configureScrollViews(in: root)
        }
    }

    private func configureScrollViews(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.verticalScroller?.controlSize = .small
        }

        view.subviews.forEach(configureScrollViews)
    }
}
