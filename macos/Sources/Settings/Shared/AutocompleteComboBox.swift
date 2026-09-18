import AppKit
import SwiftUI

struct AutocompleteComboBox: NSViewRepresentable {
    @Binding var text: String
    let values: [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, values: values)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.usesDataSource = true
        comboBox.completes = true
        comboBox.delegate = context.coordinator
        comboBox.dataSource = context.coordinator
        comboBox.stringValue = text
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        if context.coordinator.values != values {
            context.coordinator.values = values
            comboBox.reloadData()
        }
        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate, NSComboBoxDataSource {
        @Binding private var text: String
        var values: [String]

        init(text: Binding<String>, values: [String]) {
            _text = text
            self.values = values
        }

        func numberOfItems(in comboBox: NSComboBox) -> Int {
            values.count
        }

        func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
            values[index]
        }

        func comboBox(_ comboBox: NSComboBox, completedString string: String) -> String? {
            values.first {
                $0.range(of: string, options: [.anchored, .caseInsensitive]) != nil
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            text = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            text = comboBox.stringValue
        }
    }
}
