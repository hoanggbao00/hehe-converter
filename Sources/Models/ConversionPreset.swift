import Foundation

enum PresetMediaKind: String, CaseIterable {
    case image
    case video
    case audio
}

enum VideoOutputFormat: String, Codable, CaseIterable, Identifiable {
    case mp4
    case mkv
    case mov
    case gif
    case mp3
    case m4a
    case webp

    var id: Self { self }

    var label: String {
        rawValue.uppercased()
    }

    var fileExtension: String { rawValue }

    static let suggestedFormats: [Self] = [
        .mp4, .mov, .webp, .gif, .mp3, .m4a,
    ]

    static func format(matching value: String) -> Self? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first {
            $0.label.caseInsensitiveCompare(normalized) == .orderedSame
                || $0.rawValue.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    var supportsQuality: Bool {
        [.mp4, .mkv, .mov, .webp].contains(self)
    }

    var supportsResolution: Bool {
        [.mp4, .mkv, .mov, .gif, .webp].contains(self)
    }

    var supportsFPS: Bool {
        supportsResolution
    }

    var supportsAudioToggle: Bool {
        [.mp4, .mkv, .mov].contains(self)
    }

    var supportsLoop: Bool {
        [.gif, .webp].contains(self)
    }

    var supportsAudioBitrate: Bool {
        [.mp3, .m4a].contains(self)
    }

    var hasEncodingOptions: Bool {
        supportsQuality || supportsResolution || supportsFPS || supportsAudioToggle || supportsLoop || supportsAudioBitrate
    }
}

enum VideoResolution: Int, Codable, CaseIterable, Identifiable {
    case original = 0
    case p480 = 480
    case p720 = 720
    case p1080 = 1080
    case p1440 = 1440
    case p2160 = 2160

    var id: Self { self }

    var label: String {
        self == .original ? "Original" : "\(rawValue)p"
    }

    var height: Int? {
        self == .original ? nil : rawValue
    }
}

struct VideoEncodingOptions: Codable, Equatable {
    let quality: Int?
    let resolution: VideoResolution?
    let fps: Double?
    let removesAudio: Bool?
    let loopCount: Int?
    let audioBitrateKbps: Int?
}

struct VideoPreset: Codable, Equatable, Identifiable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let name: String
    let outputFormat: VideoOutputFormat
    let options: VideoEncodingOptions?
    let isBuiltIn: Bool
    let ffmpegCommand: String

    init(
        id: UUID = UUID(),
        name: String,
        outputFormat: VideoOutputFormat,
        options: VideoEncodingOptions? = nil,
        isBuiltIn: Bool = false
    ) {
        schemaVersion = Self.schemaVersion
        self.id = id
        self.name = name
        self.outputFormat = outputFormat
        self.options = options
        self.isBuiltIn = isBuiltIn
        ffmpegCommand = VideoFFmpegCommandBuilder.command(outputFormat: outputFormat, options: options)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        outputFormat = try container.decode(VideoOutputFormat.self, forKey: .outputFormat)
        options = try container.decodeIfPresent(VideoEncodingOptions.self, forKey: .options)
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        ffmpegCommand = try container.decodeIfPresent(String.self, forKey: .ffmpegCommand)
            ?? VideoFFmpegCommandBuilder.command(outputFormat: outputFormat, options: options)
    }
}

enum ImageOutputFormat: String, Codable, Identifiable {
    case jpg
    case png
    case webp
    case avif
    case gif
    case apng
    case bmp
    case tiff
    case jpegLS
    case qoi
    case tga
    case pcx
    case pam
    case pbm
    case pgm
    case ppm
    case wbmp
    case heic

    var id: Self { self }

    var label: String {
        switch self {
        case .jpegLS: "JPEG-LS"
        default: rawValue.uppercased()
        }
    }

    var fileExtension: String {
        switch self {
        case .jpegLS: "jls"
        default: rawValue
        }
    }

    func matches(fileExtension: String) -> Bool {
        let value = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch self {
        case .jpg: return ["jpg", "jpeg"].contains(value)
        default: return self.fileExtension == value
        }
    }

    static let availableFormats: [Self] = [
        .jpg, .png, .webp, .avif, .gif, .apng, .bmp, .tiff,
        .jpegLS, .qoi, .tga, .pcx, .pam, .pbm, .pgm, .ppm, .wbmp,
    ]

    static let suggestedFormats: [Self] = [
        .jpg, .png, .webp, .avif, .gif, .tiff,
    ]

    static func availableFormat(matching value: String) -> Self? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return availableFormats.first {
            $0.label.caseInsensitiveCompare(normalized) == .orderedSame
                || $0.rawValue.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    var supportsQuality: Bool {
        [.jpg, .webp, .avif].contains(self)
    }

    var supportsLossless: Bool {
        [.webp, .avif].contains(self)
    }

    var supportsPNGPrediction: Bool {
        [.png, .apng].contains(self)
    }

    var supportsTIFFCompression: Bool {
        self == .tiff
    }

    var supportsRLE: Bool {
        self == .tga
    }

    var supportsGlobalPalette: Bool {
        self == .gif
    }

    var hasEncodingOptions: Bool {
        supportsQuality || supportsLossless || supportsPNGPrediction
            || supportsTIFFCompression || supportsRLE || supportsGlobalPalette
    }
}

enum ImageResizeMode: String, Codable, CaseIterable, Identifiable {
    case fitWithin
    case exactSize
    case percentage

    var id: Self { self }

    var label: String {
        switch self {
        case .fitWithin: "Fit Within"
        case .exactSize: "Exact Size"
        case .percentage: "Percentage"
        }
    }
}

enum ImageDimensionUnit: String, Codable, CaseIterable, Identifiable {
    case pixels = "px"
    case percent = "%"

    var id: Self { self }
}

struct ImageDimension: Codable, Equatable {
    let value: Double
    let unit: ImageDimensionUnit
}

struct ImageResize: Codable, Equatable {
    let mode: ImageResizeMode
    let width: ImageDimension?
    let height: ImageDimension?
    let percentage: Double?
    let keepAspectRatio: Bool
}

enum ImagePNGPrediction: String, Codable, CaseIterable, Identifiable {
    case none
    case sub
    case up
    case avg
    case paeth
    case mixed

    var id: Self { self }
    var label: String { rawValue.capitalized }
}

enum ImageTIFFCompression: String, Codable, CaseIterable, Identifiable {
    case packbits
    case raw
    case lzw
    case deflate

    var id: Self { self }
    var label: String { rawValue.uppercased() }
}

struct ImageEncodingOptions: Codable, Equatable {
    let quality: Int?
    let lossless: Bool?
    let pngPrediction: ImagePNGPrediction?
    let tiffCompression: ImageTIFFCompression?
    let rle: Bool?
    let globalPalette: Bool?
}

struct ImagePreset: Codable, Equatable, Identifiable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let name: String
    let outputFormat: ImageOutputFormat
    let resize: ImageResize?
    let options: ImageEncodingOptions?
    let isBuiltIn: Bool
    let ffmpegCommand: String

    init(
        id: UUID = UUID(),
        name: String,
        outputFormat: ImageOutputFormat,
        resize: ImageResize? = nil,
        options: ImageEncodingOptions? = nil,
        isBuiltIn: Bool = false
    ) {
        schemaVersion = Self.schemaVersion
        self.id = id
        self.name = name
        self.outputFormat = outputFormat
        self.resize = resize
        self.options = options
        self.isBuiltIn = isBuiltIn
        ffmpegCommand = ImageFFmpegCommandBuilder.command(
            outputFormat: outputFormat,
            resize: resize,
            options: options
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(UUID.self, forKey: .id)
        outputFormat = try container.decode(ImageOutputFormat.self, forKey: .outputFormat)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? outputFormat.label
        resize = try container.decodeIfPresent(ImageResize.self, forKey: .resize)
        options = try container.decodeIfPresent(ImageEncodingOptions.self, forKey: .options)
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        ffmpegCommand = try container.decodeIfPresent(String.self, forKey: .ffmpegCommand)
            ?? ImageFFmpegCommandBuilder.command(
                outputFormat: outputFormat,
                resize: resize,
                options: options
            )
    }
}
