import AppKit
import SwiftUI

struct ScrubbableTextField: NSViewRepresentable {
    @Binding var text: String
    let step: Double
    let usesIntegerValues: Bool
    let onChange: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ScrubbingTextField {
        let field = ScrubbingTextField()
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.alignment = .left
        return field
    }

    func updateNSView(_ field: ScrubbingTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.onScrubBegan = { [weak coordinator = context.coordinator] in
            coordinator?.scrubStart = Double(coordinator?.parent.text ?? "") ?? 1
        }
        field.onScrub = { [weak coordinator = context.coordinator] distance in
            coordinator?.scrub(distance: distance)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ScrubbableTextField
        var scrubStart = 1.0

        init(_ parent: ScrubbableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onChange()
        }

        func scrub(distance: CGFloat) {
            var value = max(1, scrubStart + Double(distance) * parent.step)
            if parent.usesIntegerValues {
                value = value.rounded()
            }
            parent.text = value.rounded() == value
                ? String(Int(value))
                : String(format: "%.2f", value)
            parent.onChange()
        }
    }
}

final class ScrubbingTextField: NSTextField {
    var onScrubBegan: (() -> Void)?
    var onScrub: ((CGFloat) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let start = event.locationInWindow
        var dragged = false

        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                if !dragged {
                    window?.makeFirstResponder(self)
                    selectText(nil)
                }
                return
            }

            let distance = next.locationInWindow.x - start.x
            if !dragged, abs(distance) >= 3 {
                dragged = true
                onScrubBegan?()
            }
            if dragged {
                onScrub?(distance)
            }
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}
