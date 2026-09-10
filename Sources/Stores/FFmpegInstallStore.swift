import AppKit
import Foundation

@MainActor
final class FFmpegInstallStore: ObservableObject {
    @Published private(set) var installation = FFmpegInstall.installation
    @Published private(set) var isDownloading = false
    @Published private(set) var isVerifying = false
    @Published private(set) var progress = 0.0
    @Published private(set) var message: String?
    @Published private(set) var hasError = false
    @Published private(set) var step: FFmpegInstallStep?
    @Published private(set) var availableReleases: [FFmpegRelease] = []
    @Published private(set) var isFetchingReleases = false

    private var installTask: Task<Void, Never>?

    var isInstalled: Bool { installation != nil }

    var statusText: String {
        if isDownloading { return "Installing" }
        if isVerifying { return "Verifying" }
        return isInstalled ? "Installed" : "Not installed"
    }

    func refresh() {
        installation = FFmpegInstall.installation
    }

    func refreshAndVerifyIfNeeded() {
        refresh()
        guard FFmpegInstall.needsVerification else { return }
        verify()
    }

    func loadReleases() async {
        guard !isFetchingReleases else { return }

        isFetchingReleases = true
        availableReleases = []
        message = nil
        hasError = false
        defer { isFetchingReleases = false }
        do {
            availableReleases = try await FFmpegDistribution.fetchReleases()
        } catch {
            hasError = true
            message = error.localizedDescription
        }
    }

    func verify() {
        guard !isDownloading, !isVerifying else { return }

        isVerifying = true
        message = nil
        hasError = false

        Task {
            do {
                let verifiedInstallation = try FFmpegInstall.verifyInstalledFiles()
                installation = verifiedInstallation
                if verifiedInstallation == nil {
                    hasError = true
                    message = "FFmpeg not found in app folder or common Homebrew paths."
                }
            } catch {
                refresh()
                hasError = true
                message = error.localizedDescription
            }

            isVerifying = false
        }
    }

    func download(_ selectedRelease: FFmpegRelease? = nil) {
        guard !isDownloading else { return }

        isDownloading = true
        progress = 0
        step = .fetch
        message = nil
        hasError = false

        installTask = Task {
            do {
                let release: FFmpegRelease
                if let selectedRelease {
                    release = selectedRelease
                } else {
                    step = .fetch
                    guard let latest = try await FFmpegDistribution.fetchReleases().first else {
                        throw FFmpegReleaseError.noCompatibleRelease
                    }
                    release = latest
                    if availableReleases.isEmpty { availableReleases = [latest] }
                }

                try await FFmpegInstaller.install(
                    release: release,
                    progress: { [weak self] value in
                        Task { @MainActor in
                            self?.progress = value
                        }
                    },
                    step: { [weak self] step in
                        Task { @MainActor in
                            self?.step = step
                        }
                    }
                )

                refresh()
                progress = 1
                step = nil
                _ = try? FFmpegInstall.verifyInstalledFiles()
                refresh()
                message = nil
            } catch is CancellationError {
                refresh()
                step = nil
                message = "Download cancelled."
            } catch let error as URLError where error.code == .cancelled {
                refresh()
                step = nil
                message = "Download cancelled."
            } catch {
                refresh()
                step = nil
                hasError = true
                message = error.localizedDescription
            }

            isDownloading = false
            installTask = nil
        }
    }

    func cancel() {
        installTask?.cancel()
    }

    func openFolder() {
        do {
            try FileManager.default.createDirectory(
                at: FFmpegInstall.binDirectory,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(FFmpegInstall.binDirectory)
        } catch {
            hasError = true
            message = error.localizedDescription
        }
    }

    func deleteInstalledFiles() {
        do {
            try FFmpegInstall.deleteInstalledFiles()
            refresh()
            message = nil
            hasError = false
        } catch {
            refresh()
            hasError = true
            message = error.localizedDescription
        }
    }
}
