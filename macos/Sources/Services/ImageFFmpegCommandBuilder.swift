import Foundation

enum ImageFFmpegCommandBuilder {
    static func arguments(
        outputFormat: ImageOutputFormat,
        resize: ImageResize?,
        options: ImageEncodingOptions?,
        inputURL: URL,
        outputURL: URL
    ) -> [String] {
        var arguments = ["-i", inputURL.path]

        if let filter = scaleFilter(for: resize) {
            arguments += ["-vf", filter]
        }

        arguments += encodingArguments(for: outputFormat, options: options)
        if !outputFormat.supportsAnimation {
            arguments += ["-frames:v", "1"]
        }
        arguments += options?.moreArguments ?? []
        arguments += ["-y", outputURL.path]
        return arguments
    }

    static func command(
        outputFormat: ImageOutputFormat,
        resize: ImageResize?,
        options: ImageEncodingOptions?
    ) -> String {
        var arguments = ["ffmpeg", "-i", "\"{input}\""]

        if let filter = scaleFilter(for: resize) {
            arguments += ["-vf", "\"\(filter)\""]
        }

        arguments += encodingArguments(for: outputFormat, options: options)
        if !outputFormat.supportsAnimation {
            arguments += ["-frames:v", "1"]
        }
        arguments += options?.moreArguments ?? []
        arguments += ["-y", "\"{output}\""]
        return arguments.joined(separator: " ")
    }

    private static func scaleFilter(for resize: ImageResize?) -> String? {
        guard let resize else { return nil }

        switch resize.mode {
        case .fitWithin, .exactSize:
            guard let width = resize.width, let height = resize.height else { return nil }
            var filter = "scale=\(expression(for: width, axis: "iw")):\(expression(for: height, axis: "ih"))"
            if resize.mode == .fitWithin {
                filter += ":force_original_aspect_ratio=decrease"
            }
            return filter
        case .percentage:
            guard let percentage = resize.percentage else { return nil }
            let factor = decimal(percentage / 100)
            return "scale=iw*\(factor):ih*\(factor)"
        }
    }

    private static func expression(for dimension: ImageDimension, axis: String) -> String {
        switch dimension.unit {
        case .pixels:
            return String(Int(dimension.value.rounded()))
        case .percent:
            return "\(axis)*\(decimal(dimension.value / 100))"
        }
    }

    private static func encodingArguments(
        for format: ImageOutputFormat,
        options: ImageEncodingOptions?
    ) -> [String] {
        switch format {
        case .jpg:
            return qualityScaleArguments(options?.quality)
        case .webp:
            var arguments = ["-c:v", "libwebp"]
            if options?.lossless == true {
                arguments += ["-lossless", "1"]
            } else if let quality = options?.quality {
                arguments += ["-quality", String(quality)]
            }
            return arguments
        case .avif:
            var arguments = ["-c:v", "libaom-av1", "-still-picture", "1"]
            let crf = options?.lossless == true ? 0 : avifCRF(for: options?.quality)
            if let crf {
                arguments += ["-crf", String(crf)]
            }
            return arguments
        case .png, .apng:
            guard let prediction = options?.pngPrediction else { return [] }
            return ["-pred", prediction.rawValue]
        case .tiff:
            var arguments = ["-pix_fmt", "rgb24"]
            if let compression = options?.tiffCompression {
                arguments += ["-compression_algo", compression.rawValue]
            }
            return arguments
        case .tga:
            guard let rle = options?.rle else { return [] }
            return ["-rle", rle ? "1" : "0"]
        case .gif:
            guard let globalPalette = options?.globalPalette else { return [] }
            return ["-global_palette", globalPalette ? "1" : "0"]
        default:
            return []
        }
    }

    private static func qualityScaleArguments(_ quality: Int?) -> [String] {
        guard let quality else { return [] }
        let qscale = Int((31 - Double(quality) * 29 / 100).rounded()).clamped(to: 2...31)
        return ["-q:v", String(qscale)]
    }

    private static func avifCRF(for quality: Int?) -> Int? {
        guard let quality else { return nil }
        return Int((63 - Double(quality) * 63 / 100).rounded()).clamped(to: 0...63)
    }

    private static func decimal(_ value: Double) -> String {
        var value = String(format: "%.4f", value)
        while value.last == "0" { value.removeLast() }
        if value.last == "." { value.removeLast() }
        return value
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
