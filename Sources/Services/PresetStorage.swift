import Foundation

struct PresetStorage {
    let rootDirectory: URL
    private let defaultImagePresetMarker = ".seeded"

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

    func update(_ storedPreset: StoredImagePreset, with preset: ImagePreset) throws {
        try JSONEncoder.pretty.encode(preset).write(to: storedPreset.fileURL, options: .atomic)
    }

    func directory(for kind: PresetMediaKind) -> URL {
        rootDirectory.appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    func delete(_ storedPreset: StoredImagePreset) throws {
        try FileManager.default.removeItem(at: storedPreset.fileURL)
    }

    func seedDefaultImagePresetsIfNeeded() throws {
        let directory = directory(for: .image)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let marker = directory.appendingPathComponent(defaultImagePresetMarker)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }

        for preset in Self.defaultImagePresets {
            let file = directory.appendingPathComponent("\(slug(for: preset.name)).json")
            guard !FileManager.default.fileExists(atPath: file.path) else { continue }
            try JSONEncoder.pretty.encode(preset).write(to: file, options: .atomic)
        }

        try Data().write(to: marker, options: .atomic)
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
        ImagePreset(name: "WebP", outputFormat: .webp),
        ImagePreset(name: "PNG", outputFormat: .png),
        ImagePreset(name: "JPG", outputFormat: .jpg),
        ImagePreset(name: "BMP", outputFormat: .bmp),
        ImagePreset(name: "AVIF", outputFormat: .avif),
    ]
}

struct StoredImagePreset: Equatable, Identifiable {
    var id: UUID { preset.id }

    let preset: ImagePreset
    let fileURL: URL
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
