import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = AppSettingsStore()

    private var statusBarController: StatusBarController?
    private var ffmpegOnboardingWindowController: FFmpegOnboardingWindowController?
    private var dragPresetCoordinator: DragPresetCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(settingsStore: settingsStore)
        try? PresetStorage().seedDefaultImagePresetsIfNeeded()
        try? PresetStorage().seedDefaultVideoPresetsIfNeeded()
        dragPresetCoordinator = DragPresetCoordinator(settingsStore: settingsStore)

        guard FFmpegOnboarding.shouldShow else { return }
        FFmpegOnboarding.markPresented()
        let controller = FFmpegOnboardingWindowController()
        ffmpegOnboardingWindowController = controller
        controller.show()
    }
}

enum FFmpegOnboarding {
    static var shouldShow: Bool {
        shouldShow(
            isInstalled: FFmpegInstall.isInstalled,
            wasPresented: UserDefaults.standard.bool(
                forKey: AppConstants.DefaultsKey.didPresentFFmpegOnboarding
            )
        )
    }

    static func shouldShow(isInstalled: Bool, wasPresented: Bool) -> Bool {
        !isInstalled && !wasPresented
    }

    static func markPresented() {
        UserDefaults.standard.set(
            true,
            forKey: AppConstants.DefaultsKey.didPresentFFmpegOnboarding
        )
    }
}
