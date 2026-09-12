import AppKit
import CoreGraphics
import SwiftUI

struct ModifierShortcutRecorder: NSViewRepresentable {
    let shortcut: ModifierShortcut
    let onChange: (ModifierShortcut) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onChange = onChange
        button.setShortcut(shortcut)
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onChange = onChange
        if !button.isRecording {
            button.setShortcut(shortcut)
        }
    }
}

final class RecorderButton: NSButton {
    var onChange: ((ModifierShortcut) -> Void)?
    private(set) var isRecording = false
    private var shortcut = ModifierShortcut.default
    private var capturedModifiers: Set<ShortcutModifier> = []

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setShortcut(_ shortcut: ModifierShortcut) {
        self.shortcut = shortcut
        title = shortcut.label
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        capturedModifiers = []
        title = "Press shortcut"
        window?.makeFirstResponder(self)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        let current = Self.modifiers(from: event.modifierFlags)
        if !current.isEmpty {
            capturedModifiers.formUnion(current)
            title = ModifierShortcut(modifiers: capturedModifiers).label
        } else if !capturedModifiers.isEmpty {
            submitCapturedShortcut(key: nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            cancelRecording()
            return
        }
        guard let key = Self.shortcutKey(from: event) else { return }
        capturedModifiers.formUnion(Self.modifiers(from: event.modifierFlags))
        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
        }
        submitCapturedShortcut(key: key)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            cancelRecording()
        }
        return super.resignFirstResponder()
    }

    func cancelRecording() {
        isRecording = false
        capturedModifiers = []
        setShortcut(shortcut)
        window?.makeFirstResponder(nil)
    }

    private func submitCapturedShortcut(key: String?) {
        guard isRecording, !capturedModifiers.isEmpty else { return }

        let shortcut = ModifierShortcut(modifiers: capturedModifiers, key: key)
        setShortcut(shortcut)
        isRecording = false
        capturedModifiers = []
        onChange?(shortcut)
        window?.makeFirstResponder(nil)
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<ShortcutModifier> {
        Set(ShortcutModifier.allCases.filter { modifier in
            switch modifier {
            case .control: flags.contains(.control)
            case .option: flags.contains(.option)
            case .shift: flags.contains(.shift)
            case .command: flags.contains(.command)
            }
        })
    }

    static func shortcutKey(from event: NSEvent) -> String? {
        guard let characters = event.charactersIgnoringModifiers?.uppercased(),
              characters.count == 1,
              let character = characters.first,
              character.isASCII,
              character.isLetter || character.isNumber else { return nil }
        return String(character)
    }
}
