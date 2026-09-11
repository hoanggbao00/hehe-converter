import Foundation

enum ImageCropFFmpegCommandBuilder {
    static func arguments(inputURL: URL, outputURL: URL, cropRect: CGRect) -> [String] {
        [
            "-i", inputURL.path,
            "-vf", "crop=\(Int(cropRect.width)):\(Int(cropRect.height)):\(Int(cropRect.minX)):\(Int(cropRect.minY))",
            "-frames:v", "1",
            "-y", outputURL.path
        ]
    }
}

enum ImageCropFFmpegRunner {
    static func run(inputURL: URL, cropRect: CGRect, fileManager: FileManager = .default) async throws -> URL {
        guard let installation = FFmpegInstall.installation else {
            throw ImagePresetConversionError.ffmpegNotInstalled
        }

        let outputURL = availableOutputURL(for: inputURL, fileManager: fileManager)
        let tempURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".__hehecrop-\(UUID().uuidString)")
            .appendingPathExtension(outputURL.pathExtension)
        do {
            let process = Process()
            process.executableURL = installation.ffmpegURL
            process.arguments = ImageCropFFmpegCommandBuilder.arguments(inputURL: inputURL, outputURL: tempURL, cropRect: cropRect)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ImagePresetConversionError.commandFailed(process.terminationStatus)
            }
            guard fileManager.fileExists(atPath: tempURL.path) else {
                throw ImagePresetConversionError.commandFailed(process.terminationStatus)
            }
            try fileManager.moveItem(at: tempURL, to: outputURL)
            return outputURL
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    static func availableOutputURL(for inputURL: URL, fileManager: FileManager = .default) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let basename = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension.isEmpty ? "png" : inputURL.pathExtension

        func candidate(_ suffix: Int?) -> URL {
            let name = suffix.map { "\(basename)-cropped-\($0)" } ?? "\(basename)-cropped"
            return directory.appendingPathComponent(name).appendingPathExtension(ext)
        }

        let first = candidate(nil)
        guard fileManager.fileExists(atPath: first.path) else { return first }

        var index = 1
        while true {
            let url = candidate(index)
            if !fileManager.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }
}
