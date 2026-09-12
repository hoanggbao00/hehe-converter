enum ImageAction: String, Codable, CaseIterable, Identifiable {
    case resize = "Resize"
    case crop = "Crop"
    case compress = "Compress"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .resize: "aspectratio"
        case .crop: "crop"
        case .compress: "arrow.down.right.and.arrow.up.left"
        }
    }
}
