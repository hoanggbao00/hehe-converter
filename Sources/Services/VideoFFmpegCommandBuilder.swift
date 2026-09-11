import Foundation

enum VideoFFmpegCommandBuilder {
    enum Backend: Equatable {
        case hardware
        case software
    }

    static func command(outputFormat: VideoOutputFormat, options: VideoEncodingOptions?, backend: Backend = .hardware) -> String {
        (["ffmpeg", "-i", "\"{input}\""] + encodingArguments(for: outputFormat, options: options, backend: backend) + (options?.moreArguments ?? []) + ["-y", "\"{output}\""])
            .joined(separator: " ")
    }

    static func arguments(
        outputFormat: VideoOutputFormat,
        options: VideoEncodingOptions?,
        inputURL: URL,
        outputURL: URL,
        backend: Backend = .hardware
    ) -> [String] {
        ["-i", inputURL.path] + encodingArguments(for: outputFormat, options: options, backend: backend) + (options?.moreArguments ?? []) + ["-y", outputURL.path]
    }

    static func backends(for outputFormat: VideoOutputFormat) -> [Backend] {
        switch outputFormat {
        case .mp4, .mkv, .mov, .m4v: [.hardware, .software]
        case .avi, .webm, .flv, .gif, .mp3, .m4a, .webp: [.software]
        }
    }

    private static func encodingArguments(for format: VideoOutputFormat, options: VideoEncodingOptions?, backend: Backend) -> [String] {
        switch format {
        case .mp4:
            videoArguments(container: .mp4, options: options, backend: backend)
        case .mkv:
            videoArguments(container: .mkv, options: options, backend: backend)
        case .mov:
            videoArguments(container: .mov, options: options, backend: backend)
        case .avi:
            videoArguments(container: .avi, options: options, backend: backend)
        case .webm:
            videoArguments(container: .webm, options: options, backend: backend)
        case .flv:
            videoArguments(container: .flv, options: options, backend: backend)
        case .m4v:
            videoArguments(container: .m4v, options: options, backend: backend)
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
        case avi
        case webm
        case flv
        case m4v

        func videoCodec(backend: Backend, selectedCodec: VideoCodec?) -> String {
            if backend == .hardware, supportsHardwareEncoding {
                return selectedCodec == .hevc ? "hevc_videotoolbox" : "h264_videotoolbox"
            }
            return switch self {
            case .mp4, .mkv, .mov, .m4v: selectedCodec == .hevc ? "libx265" : "libx264"
            case .avi: "mpeg4"
            case .webm: "libvpx-vp9"
            case .flv: "flv1"
            }
        }

        var supportsHardwareEncoding: Bool {
            [.mp4, .mkv, .mov, .m4v].contains(self)
        }

        var audioCodec: String {
            switch self {
            case .avi, .flv: "libmp3lame"
            case .webm: "libopus"
            case .mp4, .mkv, .mov, .m4v: "aac"
            }
        }

        func qualityArguments(for quality: Int, backend: Backend) -> [String] {
            if backend == .hardware, supportsHardwareEncoding {
                return ["-q:v", String(VideoFFmpegCommandBuilder.videoQualityScale(for: quality))]
            }
            return switch self {
            case .mp4, .mkv, .mov, .m4v:
                ["-crf", String(VideoFFmpegCommandBuilder.h264CRF(for: quality))]
            case .webm:
                ["-crf", String(VideoFFmpegCommandBuilder.vp9CRF(for: quality)), "-b:v", "0"]
            case .avi, .flv:
                ["-q:v", String(VideoFFmpegCommandBuilder.videoQualityScale(for: quality))]
            }
        }
    }

    private static func videoArguments(container: VideoContainer, options: VideoEncodingOptions?, backend: Backend) -> [String] {
        var arguments: [String] = []
        if let filter = videoFilter(options: options) {
            arguments += ["-vf", filter]
        }
        arguments += ["-c:v", container.videoCodec(backend: backend, selectedCodec: options?.codec)]
        if let quality = options?.quality {
            arguments += container.qualityArguments(for: quality, backend: backend)
        }
        if options?.removesAudio == true {
            arguments += ["-an"]
        } else {
            arguments += ["-c:a", container.audioCodec]
        }
        if [.mp4, .mov, .m4v].contains(container) {
            arguments += ["-movflags", "+faststart"]
        }
        return arguments
    }

    private static func videoQualityScale(for quality: Int) -> Int {
        Int((31 - Double(quality.clamped(to: 1...100)) * 29 / 100).rounded()).clamped(to: 2...31)
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

    private static func vp9CRF(for quality: Int) -> Int {
        Int((63 - Double(quality.clamped(to: 1...100)) * 48 / 100).rounded()).clamped(to: 15...63)
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
