import SwiftUI

struct SettingsView: View {
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case media = "Media"
        case actions = "Actions"
        case shortcuts = "Shortcuts"
        case about = "About"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .shortcuts: "keyboard"
            case .actions: "slider.horizontal.3"
            case .media: "photo.on.rectangle.angled"
            case .about: "info.circle"
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
                case .about:
                    AboutSettingsView()
                }
            }
        }
        .frame(minWidth: 520, minHeight: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            VStack(alignment: .leading, spacing: 3) {
                if store.state == .downloading {
                    Text("Downloading v\(release.version)")
                        .font(.callout.weight(.semibold))
                } else {
                    HStack(spacing: 0) {
                        Link(destination: release.pageURL) {
                            Text("New version (\(release.version))")
                                .underline()
                        }
                        .help("Open release v\(release.version) on GitHub")

                        Text(" is available.")
                    }
                    .font(.callout.weight(.semibold))
                }
                if case .failed(let message) = store.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            if store.state == .downloading {
                ProgressView(value: store.progress)
                    .frame(maxWidth: .infinity)

                Text(store.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .frame(width: 30, alignment: .trailing)

                Button {
                    store.cancel()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.plain)
                .help("Stop download")
                .accessibilityLabel("Stop update download")
            } else {
                Spacer(minLength: 8)

                Button("Download & Reopen") {
                    store.downloadAndReopen()
                }
                .controlSize(.small)
                Button {
                    store.dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Hide this version")
                .accessibilityLabel("Hide update \(release.version)")
            }
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
