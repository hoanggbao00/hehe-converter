import SwiftUI

struct SettingsView: View {
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case media = "Media"
        case actions = "Actions"
        case shortcuts = "Shortcuts"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .shortcuts: "keyboard"
            case .actions: "slider.horizontal.3"
            case .media: "photo.on.rectangle.angled"
            }
        }
    }

    @ObservedObject var store: AppSettingsStore
    @State private var selectedTab = SettingsTab.general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 15, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.caption)
                        }
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .frame(width: 72, height: 48)
                        .contentShape(Rectangle())
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.quaternary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView(store: store)
                case .shortcuts:
                    ShortcutSettingsView(store: store)
                case .actions:
                    ActionSettingsView(store: store)
                case .media:
                    MediaSettingsView()
                }
            }
        }
        .frame(width: 520, height: 380)
    }
}
