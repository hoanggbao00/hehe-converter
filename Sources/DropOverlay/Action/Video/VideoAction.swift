enum VideoAction: String, Codable, CaseIterable, Identifiable {
    case crop = "Crop"
    case trim = "Trim"
    case speed = "Speed"
    case snapshot = "Snapshot"
    case removeMetadata = "Remove Metadata"
    case mute = "Mute"
    case transform = "Transform"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .crop: "crop"
        case .trim: "scissors"
        case .speed: "speedometer"
        case .snapshot: "camera"
        case .removeMetadata: "tag.slash"
        case .mute: "speaker.slash"
        case .transform: "arrow.up.left.and.arrow.down.right"
        }
    }

    static func actions(forFileCount fileCount: Int) -> [VideoAction] {
        guard fileCount > 1 else { return allCases }
        return [.removeMetadata, .mute, .transform]
    }
}
