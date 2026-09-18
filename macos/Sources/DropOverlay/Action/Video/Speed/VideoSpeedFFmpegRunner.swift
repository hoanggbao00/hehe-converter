import Foundation

enum VideoSpeedFFmpegCommandBuilder {
    static func arguments(inputURL: URL, outputURL: URL, speed: Double, muteAudio: Bool) -> [String] {
        let clampedSpeed = VideoSpeedMath.clamp(speed)
        let videoMultiplier = decimal(1 / clampedSpeed)
        var arguments = [
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-filter:v", "setpts=\(videoMultiplier)*PTS"
        ]
        if muteAudio {
            arguments += ["-an"]
        } else {
            arguments += ["-map", "0:a?", "-filter:a", atempoFilter(for: clampedSpeed)]
        }
        if outputURL.pathExtension.lowercased() == "webm" {
            arguments += muteAudio ? ["-c:v", "libvpx-vp9"] : ["-c:v", "libvpx-vp9", "-c:a", "libopus"]
        } else {
            arguments += muteAudio ? ["-c:v", "libx264"] : ["-c:v", "libx264", "-c:a", "aac"]
        }
        arguments += ["-y", outputURL.path]
        return arguments
    }

    static func atempoFilter(for speed: Double) -> String {
        var remaining = VideoSpeedMath.clamp(speed)
        var factors: [Double] = []
        while remaining > 2 {
            factors.append(2)
            remaining /= 2
        }
        while remaining < 0.5 {
            factors.append(0.5)
            remaining /= 0.5
        }
        factors.append(remaining)
        return factors.map { "atempo=\(decimal($0))" }.joined(separator: ",")
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.4g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

enum VideoSpeedFFmpegRunner {
    static let preset = VideoPreset(
        name: "Speed",
        outputFormat: .mp4,
        presetType: .command,
        ffmpegCommand: "ffmpeg -i \"{input}\" -map 0:v:0 -map 0:a? -filter:v setpts=0.5*PTS -filter:a atempo=2 -c:v libx264 -c:a aac -y \"{output}\""
    )

    static func runBatch(
        inputURLs: [URL],
        speed: Double,
        muteAudio: Bool,
        mode: MultipleFileConversionMode,
        maxConcurrentConversions: Int,
        cancellation: ConversionCancellationController,
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        await VideoPresetConversionRunner.runBatch(
            preset: preset(for: speed, muteAudio: muteAudio),
            inputURLs: inputURLs,
            mode: mode,
            maxConcurrentConversions: maxConcurrentConversions,
            cancellation: cancellation,
            preservesInputExtension: true,
            outputNameSuffix: outputNameSuffix(speed: speed, muteAudio: muteAudio),
            update: update
        )
    }

    static func preset(for speed: Double, muteAudio: Bool) -> VideoPreset {
        VideoPreset(
            name: "Speed",
            outputFormat: .mp4,
            presetType: .command,
            ffmpegCommand: command(speed: speed, muteAudio: muteAudio)
        )
    }

    static func command(speed: Double, muteAudio: Bool) -> String {
        let clampedSpeed = VideoSpeedMath.clamp(speed)
        let videoMultiplier = String(format: "%.4g", locale: Locale(identifier: "en_US_POSIX"), 1 / clampedSpeed)
        if muteAudio {
            return "ffmpeg -i \"{input}\" -map 0:v:0 -filter:v setpts=\(videoMultiplier)*PTS -an -c:v libx264 -y \"{output}\""
        }
        return "ffmpeg -i \"{input}\" -map 0:v:0 -map 0:a? -filter:v setpts=\(videoMultiplier)*PTS -filter:a \(VideoSpeedFFmpegCommandBuilder.atempoFilter(for: clampedSpeed)) -c:v libx264 -c:a aac -y \"{output}\""
    }

    private static func outputNameSuffix(speed: Double, muteAudio: Bool) -> String {
        let speedSuffix = VideoSpeedMath.shortLabel(for: speed)
        return muteAudio ? "speed-\(speedSuffix)-muted" : "speed-\(speedSuffix)"
    }
}
