import Foundation

enum VideoTrimFFmpegCommandBuilder {
    static func arguments(inputURL: URL, outputURL: URL, startTime: Double, endTime: Double) -> [String] {
        [
            "-ss", decimal(startTime),
            "-i", inputURL.path,
            "-t", decimal(max(0, endTime - startTime)),
            "-map", "0",
            "-c", "copy",
            "-avoid_negative_ts", "make_zero",
            "-y", outputURL.path,
        ]
    }

    static func command(startTime: Double, endTime: Double) -> String {
        "ffmpeg -ss \(decimal(startTime)) -i \"{input}\" -t \(decimal(max(0, endTime - startTime))) -map 0 -c copy -avoid_negative_ts make_zero -y \"{output}\""
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.6g", locale: Locale(identifier: "en_US_POSIX"), max(0, value))
    }
}

enum VideoTrimFFmpegRunner {
    static func runBatch(
        inputURL: URL,
        startTime: Double,
        endTime: Double,
        cancellation: ConversionCancellationController,
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        let preset = VideoPreset(
            name: "Trim",
            outputFormat: VideoOutputFormat(rawValue: inputURL.pathExtension.lowercased()) ?? .mp4,
            presetType: .command,
            ffmpegCommand: VideoTrimFFmpegCommandBuilder.command(startTime: startTime, endTime: endTime)
        )
        await VideoPresetConversionRunner.runBatch(
            preset: preset,
            inputURLs: [inputURL],
            cancellation: cancellation,
            preservesInputExtension: true,
            outputNameSuffix: "trimmed",
            update: update
        )
    }
}
