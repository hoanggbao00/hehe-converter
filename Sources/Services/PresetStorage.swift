import Foundation

struct PresetStorage {
    let rootDirectory: URL
    private let defaultImagePresetMarker = ".seeded"
    private let defaultImagePresetSeedVersion = 1
    private let defaultVideoPresetSeedVersion = 3

    init(
        rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(AppConstants.managedPresetsRelativePath, isDirectory: true)
    ) {
        self.rootDirectory = rootDirectory
    }

    func loadImagePresets() throws -> [StoredImagePreset] {
        try seedDefaultImagePresetsIfNeeded()

        let directory = directory(for: .image)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { StoredImagePreset(preset: try JSONDecoder().decode(ImagePreset.self, from: Data(contentsOf: $0)), fileURL: $0) }
    }

    func save(_ preset: ImagePreset) throws {
        let directory = directory(for: .image)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = availableFileURL(named: preset.name, in: directory)
        try JSONEncoder.pretty.encode(preset).write(to: file, options: .atomic)
    }

    func loadVideoPresets() throws -> [StoredVideoPreset] {
        try seedDefaultVideoPresetsIfNeeded()

        let directory = directory(for: .video)
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map {
            StoredVideoPreset(
                preset: try JSONDecoder().decode(VideoPreset.self, from: Data(contentsOf: $0)),
                fileURL: $0
            )
        }
    }

    func save(_ preset: VideoPreset) throws {
        let directory = directory(for: .video)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = availableFileURL(named: preset.name, in: directory)
        try JSONEncoder.pretty.encode(preset).write(to: file, options: .atomic)
    }

    func update(_ storedPreset: StoredVideoPreset, with preset: VideoPreset) throws {
        try JSONEncoder.pretty.encode(preset).write(to: storedPreset.fileURL, options: .atomic)
    }

    func update(_ storedPreset: StoredImagePreset, with preset: ImagePreset) throws {
        try JSONEncoder.pretty.encode(preset).write(to: storedPreset.fileURL, options: .atomic)
    }

    func directory(for kind: PresetMediaKind) -> URL {
        rootDirectory.appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    func delete(_ storedPreset: StoredImagePreset) throws {
        try FileManager.default.removeItem(at: storedPreset.fileURL)
    }

    func delete(_ storedPreset: StoredVideoPreset) throws {
        try FileManager.default.removeItem(at: storedPreset.fileURL)
    }

    func seedDefaultImagePresetsIfNeeded() throws {
        let directory = directory(for: .image)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let marker = directory.appendingPathComponent(defaultImagePresetMarker)
        let currentVersion = (try? String(contentsOf: marker, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            ?? 0
        guard currentVersion != defaultImagePresetSeedVersion else { return }

        if FileManager.default.fileExists(atPath: marker.path) {
            try removeBuiltInImagePresets(from: directory)
        }

        for preset in Self.defaultImagePresets {
            let file = availableFileURL(named: preset.name, in: directory)
            try JSONEncoder.pretty.encode(preset).write(to: file, options: .atomic)
        }

        try Data("\(defaultImagePresetSeedVersion)".utf8).write(to: marker, options: .atomic)
    }

    func seedDefaultVideoPresetsIfNeeded() throws {
        let directory = directory(for: .video)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let marker = directory.appendingPathComponent(defaultImagePresetMarker)
        let currentVersion = (try? String(contentsOf: marker, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            ?? 0
        guard currentVersion != defaultVideoPresetSeedVersion else { return }

        for file in try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension == "json" }) {
            guard let data = try? Data(contentsOf: file),
                  let preset = try? JSONDecoder().decode(VideoPreset.self, from: data),
                  preset.isBuiltIn else { continue }
            try FileManager.default.removeItem(at: file)
        }

        for preset in Self.defaultVideoPresets {
            let file = availableFileURL(named: preset.name, in: directory)
            try JSONEncoder.pretty.encode(preset).write(to: file, options: .atomic)
        }

        try Data("\(defaultVideoPresetSeedVersion)".utf8).write(to: marker, options: .atomic)
    }

    private func removeBuiltInImagePresets(from directory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let preset = try? JSONDecoder().decode(ImagePreset.self, from: data),
                  preset.isBuiltIn || isLegacyBuiltInImagePreset(preset) else { continue }
            try FileManager.default.removeItem(at: file)
        }
    }

    private func isLegacyBuiltInImagePreset(_ preset: ImagePreset) -> Bool {
        preset.resize == nil
            && preset.options == nil
            && ["WebP", "PNG", "JPG", "BMP", "AVIF"].contains(preset.name)
    }

    func slug(for name: String) -> String {
        let folded = name
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let scalars = folded.unicodeScalars.map { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122:
                return Character(scalar)
            default:
                return "-"
            }
        }
        let slug = String(scalars)
            .lowercased()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return slug.isEmpty ? "preset" : slug
    }

    private func availableFileURL(named name: String, in directory: URL) -> URL {
        let base = slug(for: name)
        var file = directory.appendingPathComponent("\(base).json")
        var suffix = 2
        while FileManager.default.fileExists(atPath: file.path) {
            file = directory.appendingPathComponent("\(base)-\(suffix).json")
            suffix += 1
        }
        return file
    }

    private static let defaultImagePresets: [ImagePreset] = [
        ImagePreset(name: "WebP", outputFormat: .webp, isBuiltIn: true),
        ImagePreset(name: "PNG", outputFormat: .png, isBuiltIn: true),
        ImagePreset(name: "JPG", outputFormat: .jpg, isBuiltIn: true),
        ImagePreset(name: "AVIF", outputFormat: .avif, isBuiltIn: true),
        ImagePreset(name: "TIFF", outputFormat: .tiff, isBuiltIn: true),
    ]

    private static let defaultVideoPresets: [VideoPreset] = [
        VideoPreset(name: "MP4", outputFormat: .mp4, isBuiltIn: true),
        VideoPreset(name: "MKV", outputFormat: .mkv, isBuiltIn: true),
        VideoPreset(name: "MOV", outputFormat: .mov, isBuiltIn: true),
        VideoPreset(name: "GIF", outputFormat: .gif, isBuiltIn: true),
        VideoPreset(name: "MP3", outputFormat: .mp3, isBuiltIn: true),
        VideoPreset(name: "M4A", outputFormat: .m4a, isBuiltIn: true),
        VideoPreset(
            name: "WebP",
            outputFormat: .webp,
            options: VideoEncodingOptions(
                quality: nil,
                resolution: nil,
                fps: 24,
                removesAudio: nil,
                loopCount: 0,
                audioBitrateKbps: nil
            ),
            isBuiltIn: true
        ),
    ]
}

struct StoredImagePreset: Equatable, Identifiable {
    var id: UUID { preset.id }

    let preset: ImagePreset
    let fileURL: URL
}

struct StoredVideoPreset: Equatable, Identifiable {
    var id: UUID { preset.id }

    let preset: VideoPreset
    let fileURL: URL
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
