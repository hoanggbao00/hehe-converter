import SwiftUI

struct FFmpegOnboardingView: View {
    @ObservedObject var ffmpeg: FFmpegInstallStore
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if ffmpeg.isDownloading {
                downloadProgress
            } else if ffmpeg.isInstalled {
                installed
            } else {
                introduction
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download FFmpeg")
                .font(.title2.weight(.semibold))

            Text("Hehe Converter uses FFmpeg to convert images, video, and audio.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Or set up manually by copying ffmpeg and ffprobe to:")

                Text(FFmpegInstall.binDirectory.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if ffmpeg.isVerifying {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Verifying installed FFmpeg…")
                }
                .foregroundStyle(.secondary)
            }

            if let message = ffmpeg.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(ffmpeg.hasError ? .red : .secondary)
            }

            HStack {
                Spacer()

                Button("Open Folder") {
                    ffmpeg.openFolder()
                    dismiss()
                }

                Button("Download") {
                    ffmpeg.download()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(ffmpeg.isVerifying)
            }
        }
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Installing FFmpeg")
                .font(.title2.weight(.semibold))

            HStack {
                Text(ffmpeg.step?.rawValue ?? "Preparing")
                Spacer()
                Text(ffmpeg.progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)

            ProgressView(value: ffmpeg.progress)

            if let message = ffmpeg.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(ffmpeg.hasError ? .red : .secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    ffmpeg.cancel()
                }
            }
        }
    }

    private var installed: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Installed")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.green)

            if let installation = ffmpeg.installation {
                Text("Version \(installation.version) is ready.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("OK", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

}
