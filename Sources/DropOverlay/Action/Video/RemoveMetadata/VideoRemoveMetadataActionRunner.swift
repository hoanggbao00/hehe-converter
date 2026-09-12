import Foundation

enum VideoRemoveMetadataActionRunner {
    static let preset = VideoPreset(
        name: "Remove Metadata",
        outputFormat: .mp4,
        presetType: .command,
        ffmpegCommand: "ffmpeg -i \"{input}\" -map 0 -c copy -map_metadata -1 -map_chapters -1 -y \"{output}\""
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
            outputNameSuffix: "metadata-removed",
            update: update
        )
    }
}
