import AppKit
import SwiftUI

struct ActionSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step = 1.0
    var onEditingEnded: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> MouseUpSlider {
        let slider = MouseUpSlider()
        slider.cell = SmallKnobSliderCell()
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.controlSize = .small
        slider.isContinuous = true
        update(slider, context: context)
        return slider
    }

    func updateNSView(_ slider: MouseUpSlider, context: Context) {
        context.coordinator.parent = self
        update(slider, context: context)
    }

    private func update(_ slider: MouseUpSlider, context: Context) {
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.onEditingEnded = context.coordinator.editingEnded
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ActionSlider

        init(_ parent: ActionSlider) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: NSSlider) {
            let stepped = (sender.doubleValue / parent.step).rounded() * parent.step
            parent.value = min(max(stepped, parent.range.lowerBound), parent.range.upperBound)
        }

        func editingEnded() {
            parent.onEditingEnded()
        }
    }
}

final class MouseUpSlider: NSSlider {
    var onEditingEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onEditingEnded?()
    }
}

final class SmallKnobSliderCell: NSSliderCell {
    private let knobSide: CGFloat = 12

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let trackHeight: CGFloat = 3
        let horizontalInset = knobThickness / 2
        let trackRect = NSRect(
            x: rect.minX + horizontalInset,
            y: rect.midY - trackHeight / 2,
            width: max(rect.width - horizontalInset * 2, 0),
            height: trackHeight
        )

        NSColor.separatorColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2).fill()

        guard maxValue > minValue else { return }

        let progress = CGFloat((doubleValue - minValue) / (maxValue - minValue))
        let fillWidth = min(max(progress, 0), 1) * trackRect.width
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: fillWidth,
            height: trackRect.height
        )

        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let barRect = barRect(flipped: controlView?.isFlipped ?? false)
        let drawRect = NSRect(
            x: knobRect.midX - knobSide / 2,
            y: barRect.midY - knobSide / 2,
            width: knobSide,
            height: knobSide
        )
        let path = NSBezierPath(ovalIn: drawRect)
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}
