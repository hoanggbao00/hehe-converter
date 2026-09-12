import SwiftUI

struct ActionSettingsView: View {
    private enum ActionKind: String, CaseIterable, Identifiable {
        case image = "Image"
        case video = "Video"

        var id: Self { self }
    }

    @ObservedObject var store: AppSettingsStore
    @State private var selectedKind = ActionKind.image

    var body: some View {
        Form {
            Section("Built-in Actions") {
                Picker("Type", selection: $selectedKind) {
                    ForEach(ActionKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedKind {
                case .image:
                    ForEach(ImageAction.allCases) { action in
                        ImageActionSettingsRow(action: action, store: store)
                    }
                case .video:
                    Text("No video actions yet")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Defaults") {
                Picker("Resize mode", selection: Binding(
                    get: { store.settings.imageResizeDefaultScope },
                    set: { store.setImageResizeDefaultScope($0) }
                )) {
                    ForEach(ResizeApplyScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Compress mode", selection: Binding(
                    get: { store.settings.imageCompressDefaultScope },
                    set: { store.setImageCompressDefaultScope($0) }
                )) {
                    ForEach(ResizeApplyScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .background(OverlayScrollerConfigurator())
    }
}

private struct ImageActionSettingsRow: View {
    let action: ImageAction
    @ObservedObject var store: AppSettingsStore

    var body: some View {
        Toggle(isOn: Binding(
            get: { store.settings.enabledImageActions.contains(action) },
            set: { store.setImageAction(action, isEnabled: $0) }
        )) {
            HStack(spacing: 10) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(action.rawValue)
            }
        }
    }
}
