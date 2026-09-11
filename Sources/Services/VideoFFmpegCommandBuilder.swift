import Foundation

enum VideoFFmpegCommandBuilder {
    static func command(outputFormat: VideoOutputFormat, options: VideoEncodingOptions?) -> String {
        (["ffmpeg", "-i", "\"{input}\""] + encodingArguments(for: outputFormat, options: options) + (options?.moreArguments ?? []) + ["-y", "\"{output}\""])
            .joined(separator: " ")
    }

    static func arguments(
        outputFormat: VideoOutputFormat,
        options: VideoEncodingOptions?,
        inputURL: URL,
        outputURL: URL
    ) -> [String] {
        ["-i", inputURL.path] + encodingArguments(for: outputFormat, options: options) + (options?.moreArguments ?? []) + ["-y", outputURL.path]
    }

    private static func encodingArguments(for format: VideoOutputFormat, options: VideoEncodingOptions?) -> [String] {
        switch format {
        case .mp4:
            videoArguments(container: .mp4, options: options)
        case .mkv:
            videoArguments(container: .mkv, options: options)
        case .mov:
            videoArguments(container: .mov, options: options)
        case .gif:
            gifArguments(options: options)
        case .mp3:
            audioArguments(codec: "libmp3lame", options: options)
        case .m4a:
            audioArguments(codec: "aac", options: options)
        case .webp:
            webpArguments(options: options)
        }
    }

    private enum VideoContainer {
        case mp4
        case mkv
        case mov
    }

    private static func videoArguments(container: VideoContainer, options: VideoEncodingOptions?) -> [String] {
        var arguments: [String] = []
        if let filter = videoFilter(options: options) {
            arguments += ["-vf", filter]
        }
        arguments += ["-c:v", "libx264"]
        if let quality = options?.quality {
            arguments += ["-crf", String(h264CRF(for: quality))]
        }
        if options?.removesAudio == true {
            arguments += ["-an"]
        } else {
            arguments += ["-c:a", "aac"]
        }
        if container == .mp4 || container == .mov {
            arguments += ["-movflags", "+faststart"]
        }
        return arguments
    }

    private static func gifArguments(options: VideoEncodingOptions?) -> [String] {
        let source = filterChain(options: options)
        return [
            "-filter_complex",
            "[0:v]\(source)split[v0][v1];[v0]palettegen[p];[v1][p]paletteuse",
            "-loop",
            String(options?.loopCount ?? 0),
            "-an",
        ]
    }

    private static func webpArguments(options: VideoEncodingOptions?) -> [String] {
        var arguments: [String] = []
        if let filter = videoFilter(options: options) {
            arguments += ["-vf", filter]
        }
        arguments += ["-an", "-c:v", "libwebp_anim"]
        if let quality = options?.quality {
            arguments += ["-quality", String(quality.clamped(to: 1...100))]
        }
        arguments += ["-loop", String(options?.loopCount ?? 0)]
        return arguments
    }

    private static func audioArguments(codec: String, options: VideoEncodingOptions?) -> [String] {
        var arguments = ["-vn", "-c:a", codec]
        if let bitrate = options?.audioBitrateKbps {
            arguments += ["-b:a", "\(bitrate.clamped(to: 64...320))k"]
        }
        return arguments
    }

    private static func videoFilter(options: VideoEncodingOptions?) -> String? {
        let chain = filterChain(options: options)
        return chain.isEmpty ? nil : String(chain.dropLast())
    }

    private static func filterChain(options: VideoEncodingOptions?) -> String {
        var filters: [String] = []
        if let fps = options?.fps, fps > 0 {
            filters.append("fps=\(decimal(fps))")
        }
        return filters.isEmpty ? "" : filters.joined(separator: ",") + ","
    }

    private static func h264CRF(for quality: Int) -> Int {
        Int((32 - Double(quality.clamped(to: 1...100)) * 20 / 100).rounded()).clamped(to: 12...32)
    }

    private static func decimal(_ value: Double) -> String {
        var string = String(format: "%.3f", value)
        while string.last == "0" { string.removeLast() }
        if string.last == "." { string.removeLast() }
        return string
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
