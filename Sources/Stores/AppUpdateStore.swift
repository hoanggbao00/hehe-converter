import Foundation

@MainActor
final class AppUpdateStore: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading
        case failed(String)
    }

    @Published private(set) var release: AppRelease?
    @Published private(set) var state = State.idle
    @Published private(set) var progress = 0.0

    private let defaults: UserDefaults
    private let service: AppUpdateService
    private var checked = false
    private var updateTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, service: AppUpdateService = AppUpdateService()) {
        self.defaults = defaults
        self.service = service
    }

    func check() async {
        guard !checked else { return }
        checked = true
        do {
            let latest = try await service.latestRelease()
            guard let current = AppVersion(Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? ""),
                  let available = AppVersion(latest.version),
                  available > current,
                  defaults.string(forKey: AppConstants.DefaultsKey.dismissedAppUpdateVersion)
                    != latest.version
            else { return }
            release = latest
        } catch {
            // ponytail: Update checks stay silent; expose diagnostics when app gains logging UI.
        }
    }

    func dismiss() {
        guard let release else { return }
        defaults.set(release.version, forKey: AppConstants.DefaultsKey.dismissedAppUpdateVersion)
        self.release = nil
    }

    func downloadAndReopen() {
        guard let release, state != .downloading else { return }
        state = .downloading
        progress = 0
        updateTask = Task {
            do {
                try await service.downloadAndInstall(release) { [weak self] value in
                    Task { @MainActor in
                        self?.progress = value
                    }
                }
            } catch is CancellationError {
                state = .idle
            } catch let error as URLError where error.code == .cancelled {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
            updateTask = nil
        }
    }

    func cancel() {
        updateTask?.cancel()
    }
}
