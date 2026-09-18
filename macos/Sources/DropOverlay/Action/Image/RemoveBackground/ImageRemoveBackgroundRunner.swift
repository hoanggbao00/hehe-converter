import AppKit
import CoreImage
import ImageIO
import Vision

enum ImageRemoveBackgroundError: LocalizedError {
    case unsupportedOS
    case noForeground
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedOS: "Remove Background requires macOS 14 or later."
        case .noForeground: "Could not detect foreground."
        case .encodingFailed: "Could not create transparent PNG."
        }
    }
}

enum ImageRemoveBackgroundRunner {
    private static let maskErosionRadius = 2.0
    private static let maskFeatherRadius = 0.75

    static func run(inputURL: URL, fileManager: FileManager = .default) async throws -> URL {
        try await run(
            inputURL: inputURL,
            outputURL: availableOutputURL(for: inputURL, fileManager: fileManager),
            fileManager: fileManager
        )
    }

    static func run(inputURL: URL, outputURL: URL, fileManager: FileManager = .default) async throws -> URL {
        guard #available(macOS 14.0, *) else {
            throw ImageRemoveBackgroundError.unsupportedOS
        }

        let tempURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".__hehe-background-\(UUID().uuidString)")
            .appendingPathExtension("png")

        do {
            let data = try await transparentPNGData(inputURL: inputURL)
            try data.write(to: tempURL, options: .atomic)
            try fileManager.moveItem(at: tempURL, to: outputURL)
            return outputURL
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    static func reservedOutputURLs(for inputURLs: [URL], fileManager: FileManager = .default) -> [URL] {
        var reservedPaths = Set<String>()
        return inputURLs.map { inputURL in
            let outputURL = availableOutputURL(
                for: inputURL,
                fileManager: fileManager,
                reservedPaths: reservedPaths
            )
            reservedPaths.insert(outputURL.path)
            return outputURL
        }
    }

    static func availableOutputURL(
        for inputURL: URL,
        fileManager: FileManager = .default,
        reservedPaths: Set<String> = []
    ) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let basename = inputURL.deletingPathExtension().lastPathComponent

        func candidate(_ suffix: Int?) -> URL {
            let name = suffix.map { "\(basename)-no-background-\($0)" } ?? "\(basename)-no-background"
            return directory.appendingPathComponent(name).appendingPathExtension("png")
        }

        let first = candidate(nil)
        guard fileManager.fileExists(atPath: first.path) || reservedPaths.contains(first.path) else { return first }
        var index = 1
        while fileManager.fileExists(atPath: candidate(index).path) || reservedPaths.contains(candidate(index).path) {
            index += 1
        }
        return candidate(index)
    }

    @available(macOS 14.0, *)
    private static func transparentPNGData(inputURL: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw ImageRemoveBackgroundError.encodingFailed
            }

            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            guard let observation = request.results?.first else {
                throw ImageRemoveBackgroundError.noForeground
            }

            let context = CIContext()
            let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let inputImage = CIImage(cgImage: image).cropped(to: extent)
            let maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
            let refinedMask = refinedAlphaMask(from: CIImage(cvPixelBuffer: maskBuffer), extent: extent)
            let transparentBackground = CIImage(color: .clear).cropped(to: extent)
            guard let outputImage = CIFilter(
                name: "CIBlendWithMask",
                parameters: [
                    kCIInputImageKey: inputImage,
                    kCIInputBackgroundImageKey: transparentBackground,
                    kCIInputMaskImageKey: refinedMask
                ]
            )?.outputImage?.cropped(to: extent),
            let foregroundExtent = foregroundExtent(of: refinedMask, in: extent, context: context),
            let maskedImage = context.createCGImage(outputImage.cropped(to: foregroundExtent), from: foregroundExtent),
            let representation = NSBitmapImageRep(cgImage: maskedImage).representation(using: .png, properties: [:]) else {
                throw ImageRemoveBackgroundError.encodingFailed
            }
            return representation
        }.value
    }

    @available(macOS 14.0, *)
    private static func refinedAlphaMask(from mask: CIImage, extent: CGRect) -> CIImage {
        // ponytail: native Vision gives segmentation, not color decontamination; upgrade path is dedicated matting.
        let erodedMask = mask
            .cropped(to: extent)
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: maskErosionRadius])
        return erodedMask
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: maskFeatherRadius])
            .cropped(to: extent)
    }

    private static func foregroundExtent(
        of mask: CIImage,
        in extent: CGRect,
        context: CIContext
    ) -> CGRect? {
        let width = Int(extent.width)
        let height = Int(extent.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            context.render(
                mask,
                toBitmap: baseAddress,
                rowBytes: width * 4,
                bounds: extent,
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        return maskBounds(width: width, height: height, pixels: pixels)
    }

    static func maskBounds(width: Int, height: Int, pixels: [UInt8]) -> CGRect? {
        guard width > 0, height > 0, pixels.count >= width * height * 4 else { return nil }
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4] != 0 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
