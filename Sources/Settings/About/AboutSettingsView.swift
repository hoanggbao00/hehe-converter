import SwiftUI

struct AboutSettingsView: View {
    @State private var releaseNotes: AppReleaseNotes?
    @State private var message: String?

    private let service = AppUpdateService()
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    var body: some View {
        Form {
            Section("Application") {
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)
            }

            Section("Release Notes") {
                if let releaseNotes {
                    ScrollView {
                        Text(releaseNotes.body.isEmpty ? "No release notes." : releaseNotes.body)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 150)

                    Link("Open release on GitHub", destination: releaseNotes.pageURL)
                } else if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading release notes...")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .background(OverlayScrollerConfigurator())
        .task(id: version) {
            await loadReleaseNotes()
        }
    }

    private func loadReleaseNotes() async {
        releaseNotes = nil
        message = nil
        do {
            releaseNotes = try await service.releaseNotes(for: version)
        } catch {
            message = "Could not load release notes for v\(version)."
        }
    }
}
