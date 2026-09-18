enum ImageAction: String, Codable, CaseIterable, Identifiable {
    case resize = "Resize"
    case crop = "Crop"
    case compress = "Compress"
    case ocr = "OCR"
    case removeBackground = "Remove BG"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .resize: "aspectratio"
        case .crop: "crop"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .ocr: "text.viewfinder"
        case .removeBackground: "person.crop.circle.badge.minus"
        }
    }
}
