import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class DragPresetCoordinator {
    private let settingsStore: AppSettingsStore
    private let presetStorage: PresetStorage
    private let overlay = PresetOverlayWindowController()
    private var progressOverlays: [ConversionProgressWindowController] = []
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var settingsCancellable: AnyCancellable?
    private var dragPollTimer: Timer?
    private var draggedFileURLs: [URL] = []
    private var dragStartedInFinder = false
    private var dragModifierFlags: NSEvent.ModifierFlags = []
    private var isDragGestureActive = false
    private var isFinishingDrag = false

    init(
        settingsStore: AppSettingsStore,
        presetStorage: PresetStorage = PresetStorage()
    ) {
        self.settingsStore = settingsStore
        self.presetStorage = presetStorage

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp, .flagsChanged]
        ) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp, .flagsChanged]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }

        settingsCancellable = settingsStore.$settings.sink { [weak self] settings in
            if !settings.isEnabled {
                self?.overlay.hide()
            }
        }

        let timer = Timer(timeInterval: 1 / 30, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.pollDragState()
            }
        }
        dragPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseUp {
            if !overlay.isVisible {
                endDrag()
            }
            return
        }

        dragModifierFlags = event.modifierFlags
        if event.type == .leftMouseDragged {
            isDragGestureActive = true
            beginOrRefreshDrag()
        }
        evaluateDrag()
    }

    private func pollDragState() {
        guard isDragGestureActive else { return }
        if draggedFileURLs.isEmpty {
            beginOrRefreshDrag()
        }
        evaluateDrag()
    }

    private func beginOrRefreshDrag() {
        let urls = draggedImageURLs()
        guard !urls.isEmpty else { return }
        if draggedFileURLs.isEmpty {
            dragStartedInFinder = isFinderFrontmost
        }
        draggedFileURLs = urls
    }

    private func evaluateDrag() {
        guard isDragGestureActive,
              shortcutMatches(dragModifierFlags),
              dragStartedInFinder,
              !draggedFileURLs.isEmpty else {
            overlay.hide()
            return
        }

        do {
            let presets = try dropPresets(for: draggedFileURLs)
            guard !presets.isEmpty else {
                overlay.hide()
                return
            }
            overlay.show(
                presets: presets,
                fileURLs: draggedFileURLs,
                near: NSEvent.mouseLocation,
                onDrop: { [weak self] in self?.finishDrag() }
            )
            overlay.updateSelection(at: NSEvent.mouseLocation)
        } catch {
            overlay.hide()
        }
    }

    private func endDrag() {
        draggedFileURLs = []
        dragStartedInFinder = false
        dragModifierFlags = []
        isDragGestureActive = false
        overlay.hide()
    }

    private func finishDrag() {
        guard !isFinishingDrag else { return }
        isFinishingDrag = true
        defer { isFinishingDrag = false }

        let conversion = overlay.selectedPreset().map { preset in
            (preset: preset, inputURLs: draggedFileURLs)
        }
        endDrag()

        guard let conversion else { return }
        let progressOverlay = ConversionProgressWindowController()
        progressOverlays.append(progressOverlay)
        progressOverlay.onDismiss = { [weak self, weak progressOverlay] in
            guard let progressOverlay else { return }
            self?.progressOverlays.removeAll { $0 === progressOverlay }
        }
        let offset = CGFloat(progressOverlays.count - 1) * 92
        progressOverlay.show(
            title: "Converting to \(conversion.preset.outputLabel)",
            near: NSPoint(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y - offset)
        )
        let settings = settingsStore.settings
        let cancellation = ConversionCancellationController()
        progressOverlay.onCancelItem = { cancellation.cancel($0) }
        let conversionTask = Task {
            switch conversion.preset {
            case let .image(preset):
                await ImagePresetConversionRunner.runBatch(
                    preset: preset,
                    inputURLs: conversion.inputURLs,
                    mode: settings.multipleFileConversionMode,
                    maxConcurrentConversions: settings.maxConcurrentConversions,
                    cancellation: cancellation
                ) { [weak progressOverlay] update in
                    Task { @MainActor in
                        progressOverlay?.update(update)
                    }
                }
            case let .video(preset):
                await VideoPresetConversionRunner.runBatch(
                    preset: preset,
                    inputURLs: conversion.inputURLs,
                    mode: settings.multipleFileConversionMode,
                    maxConcurrentConversions: settings.maxConcurrentConversions,
                    cancellation: cancellation
                ) { [weak progressOverlay] update in
                    Task { @MainActor in
                        progressOverlay?.update(update)
                    }
                }
            case let .audio(preset):
                await VideoPresetConversionRunner.runBatch(
                    preset: preset,
                    inputURLs: conversion.inputURLs,
                    mode: settings.multipleFileConversionMode,
                    maxConcurrentConversions: settings.maxConcurrentConversions,
                    cancellation: cancellation
                ) { [weak progressOverlay] update in
                    Task { @MainActor in
                        progressOverlay?.update(update)
                    }
                }
            }
        }
        progressOverlay.onCancel = { conversionTask.cancel() }
    }

    private func dropPresets(for urls: [URL]) throws -> [DropPreset] {
        if urls.allSatisfy(isImageURL) {
            return try presetStorage.loadImagePresets()
                .map(\.preset)
                .filter { preset in
                    urls.contains { !preset.outputFormat.matches(fileExtension: $0.pathExtension) }
                }
                .map(DropPreset.image)
        }

        if urls.allSatisfy(isVideoURL) {
            let videoPresets = try presetStorage.loadVideoPresets()
                .map(\.preset)
                .filter { preset in
                    urls.contains { preset.outputFormat.fileExtension != $0.pathExtension.lowercased() }
                }
                .map(DropPreset.video)
            let audioPresets = try presetStorage.loadAudioPresets()
                .map(\.preset)
                .map(DropPreset.audio)
            return videoPresets + audioPresets
        }

        if urls.allSatisfy(isAudioURL) {
            return try presetStorage.loadAudioPresets()
                .map(\.preset)
                .filter { preset in
                    urls.contains { preset.outputFormat.fileExtension != $0.pathExtension.lowercased() }
                }
                .map(DropPreset.audio)
        }

        return []
    }

    private func shortcutMatches(_ flags: NSEvent.ModifierFlags) -> Bool {
        let active = Set(ShortcutModifier.allCases.filter { modifier in
            switch modifier {
            case .control: flags.contains(.control)
            case .option: flags.contains(.option)
            case .shift: flags.contains(.shift)
            case .command: flags.contains(.command)
            }
        })
        return active == settingsStore.settings.shortcuts[.showConversionPresets].modifiers
    }

    private var isFinderFrontmost: Bool {
        settingsStore.settings.isEnabled
            && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    private func draggedImageURLs() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let urls = NSPasteboard(name: .drag).readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] else { return [] }

        return urls.filter { isImageURL($0) || isVideoURL($0) || isAudioURL($0) }
    }

    private func isImageURL(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    private func isVideoURL(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie)
    }

    private func isAudioURL(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .audio)
    }
}
