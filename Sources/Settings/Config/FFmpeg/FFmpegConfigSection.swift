import SwiftUI

struct FFmpegConfigSection: View {
    @ObservedObject var ffmpeg: FFmpegInstallStore
    @Binding var confirmsDelete: Bool
    @State private var showsVersionPicker = false

    var body: some View {
        Section {
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
        } footer: {
            Divider()
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
                    downloadButton
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
                downloadButton
            }
        }
    }

    private var downloadButton: some View {
        Button("Download") {
            showsVersionPicker = true
        }
        .popover(isPresented: $showsVersionPicker, arrowEdge: .bottom) {
            FFmpegVersionPicker(ffmpeg: ffmpeg, isPresented: $showsVersionPicker)
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
