import SwiftUI

struct ConfigSettingsView: View {
    @StateObject private var ffmpeg = FFmpegInstallStore()
    @State private var confirmsDelete = false
    @State private var showsVersionPicker = false

    var body: some View {
        Form {
            Section() {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        Text("Source")
                            .fontWeight(.medium)
                        installValue
                    }

                    GridRow {
                        Text("Status")
                            .foregroundStyle(.secondary)
                        statusValue
                    }

                    if let installation = ffmpeg.installation, !installation.isVerified {
                        GridRow {
                            Text("verify")
                                .foregroundStyle(.secondary)
                            Text("Not verified")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let installation = ffmpeg.installation, !installation.hasFFprobe {
                        GridRow {
                            Text("ffprobe")
                                .foregroundStyle(.secondary)
                            Text("Missing")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                HStack {
                    Spacer()
                    actionButtons
                }

                if ffmpeg.isDownloading {
                    HStack {
                        Text(ffmpeg.step?.rawValue ?? "Preparing")
                        Spacer()
                        Text(ffmpeg.progress, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let message = ffmpeg.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(ffmpeg.hasError ? .red : .secondary)
                }

            }
        }
        .formStyle(.grouped)
        .task {
            ffmpeg.refreshAndVerifyIfNeeded()
        }
        .confirmationDialog(
            "Delete ffmpeg & ffprobe?",
            isPresented: $confirmsDelete
        ) {
            Button("Delete", role: .destructive) {
                ffmpeg.deleteInstalledFiles()
            }
        } message: {
            Text("You can re-download them anytime in Config settings.")
        }
    }

    private var statusValue: some View {
        HStack(spacing: 5) {
            Image(systemName: ffmpeg.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ffmpeg.isInstalled ? .green : .red)
            Text(ffmpeg.statusText)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if ffmpeg.isDownloading {
            ProgressView(value: ffmpeg.progress)
                .frame(maxWidth: .infinity)
            Button("Cancel", role: .cancel) {
                ffmpeg.cancel()
            }
        } else if ffmpeg.isVerifying {
            ProgressView()
                .controlSize(.small)
        } else if ffmpeg.isInstalled {
            HStack {
                Button("Verify") {
                    ffmpeg.verify()
                }
                Button("Open Folder") {
                    ffmpeg.openFolder()
                }
                if ffmpeg.installation?.source == .user {
                    Button("Download") {
                        showsVersionPicker = true
                    }
                    .popover(isPresented: $showsVersionPicker, arrowEdge: .bottom) {
                        versionPicker
                    }
                }
                if ffmpeg.installation?.source == .github {
                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Text("Delete")
                            .foregroundStyle(.red)
                    }
                }
            }
        } else {
            HStack {
                Button("Verify") {
                    ffmpeg.verify()
                }
                Button("Open Folder") {
                    ffmpeg.openFolder()
                }
                Button("Download") {
                    showsVersionPicker = true
                }
                .popover(isPresented: $showsVersionPicker, arrowEdge: .bottom) {
                    versionPicker
                }
            }
        }
    }

    private var versionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ffmpeg.isFetchingReleases {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching versions…")
                }
                .foregroundStyle(.secondary)
            } else if ffmpeg.availableReleases.isEmpty {
                Text(ffmpeg.message ?? "No versions available.")
                    .foregroundStyle(ffmpeg.hasError ? .red : .secondary)
                Button("Retry") {
                    Task { await ffmpeg.loadReleases() }
                }
            } else {
                ForEach(Array(ffmpeg.availableReleases.enumerated()), id: \.element.id) { index, release in
                    Button(index == 0 ? "Latest (\(release.version))" : release.version) {
                        showsVersionPicker = false
                        ffmpeg.download(release)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 180)
        .task {
            await ffmpeg.loadReleases()
        }
    }

    @ViewBuilder
    private var installValue: some View {
        if let installation = ffmpeg.installation {
            switch installation.source {
            case .github:
                HStack(spacing: 4) {
                    Link(
                        FFmpegDistribution.repository,
                        destination: installation.sourceURL ?? FFmpegDistribution.repositoryURL
                    )
                    Text("(\(installation.version))")
                        .foregroundStyle(.secondary)
                }
            case .user:
                Text("User (\(installation.version))")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Required for media conversion")
                .foregroundStyle(.secondary)
        }
    }
}
