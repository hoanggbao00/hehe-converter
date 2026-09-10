import Foundation

enum PresetMediaKind: String, CaseIterable {
    case image
    case video
    case audio
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
    case jpeg2000
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
        case .jpeg2000: "JPEG 2000"
        case .jpegLS: "JPEG-LS"
        default: rawValue.uppercased()
        }
    }

    static let availableFormats: [Self] = [
        .jpg, .png, .webp, .avif, .gif, .apng, .bmp, .tiff,
        .jpeg2000, .jpegLS, .qoi, .tga, .pcx, .pam, .pbm, .pgm, .ppm, .wbmp,
    ]

    static func availableFormat(matching value: String) -> Self? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return availableFormats.first {
            $0.label.caseInsensitiveCompare(normalized) == .orderedSame
                || $0.rawValue.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    var supportsQuality: Bool {
        [.jpg, .webp, .avif, .jpeg2000].contains(self)
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
    static let schemaVersion = 5

    let schemaVersion: Int
    let id: UUID
    let name: String
    let outputFormat: ImageOutputFormat
    let resize: ImageResize?
    let options: ImageEncodingOptions?
    let ffmpegCommand: String

    init(
        id: UUID = UUID(),
        name: String,
        outputFormat: ImageOutputFormat,
        resize: ImageResize? = nil,
        options: ImageEncodingOptions? = nil
    ) {
        schemaVersion = Self.schemaVersion
        self.id = id
        self.name = name
        self.outputFormat = outputFormat
        self.resize = resize
        self.options = options
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
        ffmpegCommand = try container.decodeIfPresent(String.self, forKey: .ffmpegCommand)
            ?? ImageFFmpegCommandBuilder.command(
                outputFormat: outputFormat,
                resize: resize,
                options: options
            )
    }
}
