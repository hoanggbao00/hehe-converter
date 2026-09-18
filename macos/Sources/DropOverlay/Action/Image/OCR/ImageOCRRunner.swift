import Foundation
import Vision

enum ImageOCRError: LocalizedError {
    case noText

    var errorDescription: String? {
        switch self {
        case .noText: "No text found."
        }
    }
}

enum ImageOCRRunner {
    static func recognize(inputURLs: [URL]) async throws -> String {
        var results: [(URL, String)] = []
        for inputURL in inputURLs {
            results.append((inputURL, try await recognize(inputURL: inputURL)))
        }

        let nonEmptyResults = results.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmptyResults.isEmpty else { throw ImageOCRError.noText }

        if nonEmptyResults.count == 1 {
            return nonEmptyResults[0].1
        }

        return nonEmptyResults
            .map { "## \($0.0.lastPathComponent)\n\n\($0.1)" }
            .joined(separator: "\n\n")
    }

    private static func recognize(inputURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try recognizeSync(inputURL: inputURL))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func recognizeSync(inputURL: URL) throws -> String {
        var requestError: Error?
        let request = VNRecognizeTextRequest { request, error in
            requestError = error
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = preferredLanguages(for: request)

        let handler = VNImageRequestHandler(url: inputURL, options: [:])
        try handler.perform([request])
        if let requestError { throw requestError }

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private static func preferredLanguages(for request: VNRecognizeTextRequest) -> [String] {
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let preferred = ["vi-VN", "en-US"]
        let matched = preferred.filter(supported.contains)
        return matched.isEmpty ? [] : matched
    }
}
