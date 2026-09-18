import Foundation

enum VideoMuteActionRunner {
    static let preset = VideoPreset(
        name: "Mute",
        outputFormat: .mp4,
        presetType: .command,
        ffmpegCommand: "ffmpeg -i \"{input}\" -map 0 -c copy -an -y \"{output}\""
    )

    static func runBatch(
        inputURLs: [URL],
        mode: MultipleFileConversionMode,
        maxConcurrentConversions: Int,
        cancellation: ConversionCancellationController,
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        await VideoPresetConversionRunner.runBatch(
            preset: preset,
            inputURLs: inputURLs,
            mode: mode,
            maxConcurrentConversions: maxConcurrentConversions,
            cancellation: cancellation,
            preservesInputExtension: true,
            outputNameSuffix: "muted",
            update: update
        )
    }
}
