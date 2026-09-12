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
    @StateObject private var appUpdate = AppUpdateStore()

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

            if let release = appUpdate.release {
                AppUpdateBanner(release: release, store: appUpdate)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

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
        .task {
            await appUpdate.check()
        }
    }
}

private struct AppUpdateBanner: View {
    let release: AppRelease
    @ObservedObject var store: AppUpdateStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hehe Converter \(release.version) is available")
                    .font(.callout.weight(.semibold))
                if case .failed(let message) = store.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if store.state == .downloading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Download & Reopen") {
                    store.downloadAndReopen()
                }
                .controlSize(.small)
            }

            Button {
                store.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .disabled(store.state == .downloading)
            .help("Hide this version")
            .accessibilityLabel("Hide update \(release.version)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.09))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.blue.opacity(0.25))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
