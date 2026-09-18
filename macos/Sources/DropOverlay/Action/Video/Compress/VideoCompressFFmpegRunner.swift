import Foundation

enum VideoCompressError: LocalizedError {
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(fileExtension):
            "Compress does not support .\(fileExtension) videos yet."
        }
    }
}

enum VideoCompressFFmpegCommandBuilder {
    static let supportedExtensions: Set<String> = ["mp4", "mkv", "mov", "avi", "webm", "flv", "m4v"]

    static func arguments(inputURL: URL, outputURL: URL, settings: VideoCompressSettings) throws -> [String] {
        let fileExtension = inputURL.pathExtension.lowercased()
        return try arguments(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            fileExtension: fileExtension,
            settings: settings
        )
    }

    private static func arguments(
        inputPath: String,
        outputPath: String,
        fileExtension: String,
        settings: VideoCompressSettings
    ) throws -> [String] {
        guard supportedExtensions.contains(fileExtension) else {
            throw VideoCompressError.unsupportedFormat(fileExtension)
        }

        var arguments = ["-i", inputPath, "-map", "0:v:0"]
        if !settings.mutesAudio { arguments += ["-map", "0:a?"] }
        if settings.removesMetadata { arguments += ["-map_metadata", "-1"] }
        arguments += ["-vf", filters(settings)]
        arguments += codecArguments(for: fileExtension, settings: settings)
        arguments += settings.mutesAudio ? ["-an"] : ["-c:a", "copy"]
        if ["mp4", "mov", "m4v"].contains(fileExtension) { arguments += ["-movflags", "+faststart"] }
        arguments += ["-y", outputPath]
        return arguments
    }

    static func command(settings: VideoCompressSettings, fileExtension: String) throws -> String {
        try arguments(inputPath: "{input}", outputPath: "{output}", fileExtension: fileExtension, settings: settings)
            .map { $0.contains(" ") || $0.contains("{") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
    }

    private static func filters(_ settings: VideoCompressSettings) -> String {
        let scale: String
        switch settings.unit {
        case .percent:
            let width = decimal(settings.width / 100)
            let height = decimal(settings.height / 100)
            scale = "scale=trunc(iw*\(width)/2)*2:trunc(ih*\(height)/2)*2:flags=lanczos"
        case .pixels:
            scale = "scale=\(even(settings.width)):\(even(settings.height)):flags=lanczos"
        }
        return "\(scale),fps=\(decimal(settings.fps))"
    }

    private static func codecArguments(for fileExtension: String, settings: VideoCompressSettings) -> [String] {
        let bitrate = "\(settings.bitrateKbps)k"
        let bitrateCap = ["-maxrate", bitrate, "-bufsize", "\(settings.bitrateKbps * 2)k"]
        switch fileExtension {
        case "webm":
            return ["-c:v", "libvpx-vp9", "-crf", "\(vp9CRF(settings.quality))", "-b:v", bitrate] + bitrateCap
        case "avi":
            return ["-c:v", "mpeg4", "-q:v", "\(qualityScale(settings.quality))"] + bitrateCap
        case "flv":
            return ["-c:v", "flv1", "-q:v", "\(qualityScale(settings.quality))"] + bitrateCap
        default:
            return ["-c:v", "libx264", "-crf", "\(h264CRF(settings.quality))"] + bitrateCap
        }
    }

    private static func h264CRF(_ quality: Int) -> Int {
        min(max(Int((32 - Double(quality) * 20 / 100).rounded()), 12), 32)
    }

    private static func vp9CRF(_ quality: Int) -> Int {
        min(max(Int((63 - Double(quality) * 48 / 100).rounded()), 15), 63)
    }

    private static func qualityScale(_ quality: Int) -> Int {
        min(max(Int((31 - Double(quality) * 29 / 100).rounded()), 2), 31)
    }

    private static func even(_ value: Double) -> Int {
        max(2, Int(value.rounded()) / 2 * 2)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.4g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

enum VideoCompressFFmpegRunner {
    static func runBatch(
        inputURLs: [URL],
        settings: VideoCompressSettings,
        mode: MultipleFileConversionMode,
        maxConcurrentConversions: Int,
        cancellation: ConversionCancellationController,
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        guard let first = inputURLs.first else { return }
        do {
            let fileExtension = first.pathExtension.lowercased()
            guard inputURLs.allSatisfy({ $0.pathExtension.lowercased() == fileExtension }) else {
                await runMixedBatch(inputURLs: inputURLs, settings: settings, cancellation: cancellation, update: update)
                return
            }
            let preset = try preset(settings: settings, fileExtension: fileExtension)
            await VideoPresetConversionRunner.runBatch(
                preset: preset,
                inputURLs: inputURLs,
                mode: mode,
                maxConcurrentConversions: maxConcurrentConversions,
                cancellation: cancellation,
                preservesInputExtension: true,
                outputNameSuffix: "compressed",
                update: update
            )
        } catch {
            update(.init(state: .failed, progress: 1, subtitle: error.localizedDescription))
        }
    }

    private static func runMixedBatch(
        inputURLs: [URL],
        settings: VideoCompressSettings,
        cancellation: ConversionCancellationController,
        update: @escaping @Sendable (ImagePresetConversionUpdate) -> Void
    ) async {
        for inputURL in inputURLs {
            guard !Task.isCancelled else { return }
            do {
                let preset = try preset(settings: settings, fileExtension: inputURL.pathExtension.lowercased())
                await VideoPresetConversionRunner.runBatch(
                    preset: preset,
                    inputURLs: [inputURL],
                    cancellation: cancellation,
                    preservesInputExtension: true,
                    outputNameSuffix: "compressed",
                    update: update
                )
            } catch {
                update(.init(state: .failed, progress: 1, subtitle: error.localizedDescription))
            }
        }
    }

    private static func preset(settings: VideoCompressSettings, fileExtension: String) throws -> VideoPreset {
        guard let format = VideoOutputFormat.format(matching: fileExtension) else {
            throw VideoCompressError.unsupportedFormat(fileExtension)
        }
        return VideoPreset(
            name: "Compress",
            outputFormat: format,
            presetType: .command,
            ffmpegCommand: "ffmpeg " + (try VideoCompressFFmpegCommandBuilder.command(
                settings: settings,
                fileExtension: fileExtension
            ))
        )
    }
}
