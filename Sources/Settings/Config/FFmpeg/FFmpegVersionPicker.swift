import SwiftUI

struct FFmpegVersionPicker: View {
    @ObservedObject var ffmpeg: FFmpegInstallStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ffmpeg.isFetchingReleases {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching versions...")
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
                        isPresented = false
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
}
