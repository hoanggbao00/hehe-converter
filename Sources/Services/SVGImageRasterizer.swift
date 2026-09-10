import AppKit
import Foundation
import WebKit

enum SVGImageRasterizer {
    static let defaultSize = CGSize(width: 512, height: 512)

    @MainActor
    static func rasterize(inputURL: URL, outputURL: URL) async throws {
        let size = try SVGViewport.size(for: inputURL)
        if let data = nativePNGData(inputURL: inputURL, size: size) {
            try write(data, to: outputURL)
            return
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(
            frame: CGRect(origin: .zero, size: size),
            configuration: configuration
        )
        webView.underPageBackgroundColor = .clear

        let delegate = SVGNavigationDelegate()
        webView.navigationDelegate = delegate
        try await delegate.load(inputURL, in: webView)

        let snapshotConfiguration = WKSnapshotConfiguration()
        snapshotConfiguration.rect = CGRect(origin: .zero, size: size)
        snapshotConfiguration.snapshotWidth = NSNumber(value: Double(size.width))
        snapshotConfiguration.afterScreenUpdates = true

        let image = try await webView.takeSnapshot(configuration: snapshotConfiguration)
        guard let data = image.pngData else {
            throw SVGImageRasterizerError.cannotCreatePNG
        }
        try write(data, to: outputURL)
        webView.navigationDelegate = nil
    }

    private static func nativePNGData(inputURL: URL, size: CGSize) -> Data? {
        guard let image = NSImage(contentsOf: inputURL),
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width.rounded()),
                pixelsHigh: Int(size.height.rounded()),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: .alphaFirst,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current = context
        context?.cgContext.clear(CGRect(origin: .zero, size: size))
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func write(_ data: Data, to outputURL: URL) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
    }
}

enum SVGViewport {
    static func size(for inputURL: URL) throws -> CGSize {
        try size(from: Data(contentsOf: inputURL))
    }

    static func size(from data: Data) throws -> CGSize {
        let parser = XMLParser(data: data)
        let delegate = SVGRootParser()
        parser.delegate = delegate
        _ = parser.parse()
        return normalizedSize(width: delegate.width, height: delegate.height)
            ?? normalizedSize(width: delegate.viewBoxWidth, height: delegate.viewBoxHeight)
            ?? SVGImageRasterizer.defaultSize
    }

    private static func normalizedSize(width: Double?, height: Double?) -> CGSize? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}

private final class SVGRootParser: NSObject, XMLParserDelegate {
    private(set) var width: Double?
    private(set) var height: Double?
    private(set) var viewBoxWidth: Double?
    private(set) var viewBoxHeight: Double?
    private var didReadRoot = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard !didReadRoot else {
            parser.abortParsing()
            return
        }
        didReadRoot = true
        guard elementName.caseInsensitiveCompare("svg") == .orderedSame else { return }

        width = Self.numericLength(attributeDict["width"])
        height = Self.numericLength(attributeDict["height"])

        let viewBox = attributeDict["viewBox"] ?? attributeDict["viewbox"]
        let values = viewBox?
            .split { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }
            .compactMap { Double($0) }
        if let values, values.count == 4 {
            viewBoxWidth = values[2]
            viewBoxHeight = values[3]
        }
    }

    private static func numericLength(_ value: String?) -> Double? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasSuffix("%") else { return nil }
        let numericText = trimmed.prefix { character in
            character.isNumber || character == "." || character == "-"
        }
        guard let numeric = Double(numericText) else { return nil }
        let unit = trimmed.dropFirst(numericText.count).lowercased()
        let factor: Double
        switch unit {
        case "", "px": factor = 1
        case "in": factor = 96
        case "cm": factor = 96 / 2.54
        case "mm": factor = 96 / 25.4
        case "q": factor = 96 / 101.6
        case "pt": factor = 96 / 72
        case "pc": factor = 16
        default: return nil
        }
        return numeric * factor
    }
}

@MainActor
private final class SVGNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ inputURL: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadFileURL(
                inputURL,
                allowingReadAccessTo: inputURL.deletingLastPathComponent()
            )
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

enum SVGImageRasterizerError: LocalizedError {
    case cannotCreatePNG

    var errorDescription: String? {
        switch self {
        case .cannotCreatePNG:
            "Could not rasterize SVG to PNG."
        }
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
