import SwiftUI

struct ShortcutSettingsView: View {
    @ObservedObject var store: AppSettingsStore

    var body: some View {
        Form {
            Section("Drag") {
                ForEach(ShortcutAction.allCases.filter { $0.section == "Drag" }) { action in
                    HStack(spacing: 12) {
                        Text(action.title)
                        Spacer(minLength: 12)

                        Button {
                            store.setShortcut(action.defaultShortcut, for: action)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Reset to default (\(action.defaultShortcut.label))")
                        .opacity(store.settings.shortcuts[action] == action.defaultShortcut ? 0 : 1)
                        .disabled(store.settings.shortcuts[action] == action.defaultShortcut)
                        .frame(width: 18)

                        ModifierShortcutRecorder(shortcut: store.settings.shortcuts[action]) {
                            store.setShortcut($0, for: action)
                        }
                        .frame(width: 144, height: 26)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
