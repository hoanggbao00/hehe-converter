import AppKit
import SwiftUI

@MainActor
final class ImageCompressWindowController {
    private let panel = OverlayPanelController()

    func show(inputURLs: [URL], near mouseLocation: NSPoint, defaultScope: ResizeApplyScope) {
        let models = inputURLs.map(ImageCompressModel.init(inputURL:))
        guard !models.isEmpty else { return }
        let sharedModel = models[0]
        let baseHeight = models.contains(where: \.supportsFPS)
            ? ImageCompressView.animatedPanelHeight
            : ImageCompressView.panelHeight
        let height = baseHeight + (models.count > 1 ? 35 : 0)
        let width = models.count > 1 && defaultScope == .each
            ? ImageCompressView.multiColumnWidth * CGFloat(min(models.count, 3))
            : ImageCompressView.singleWidth
        let size = NSSize(width: width, height: height)

        panel.show(
            size: size,
            near: mouseLocation,
            content: ImageCompressView(
                models: models,
                sharedModel: sharedModel,
                defaultScope: defaultScope
            ) { [weak self] in
                self?.hide()
            } apply: { model in
                do {
                    return try await model.applyCompress()
                } catch {
                    model.errorMessage = error.localizedDescription
                    return nil
                }
            } applyAll: { sharedModel, models in
                sharedModel.isApplying = true
                sharedModel.errorMessage = nil
                defer { sharedModel.isApplying = false }
                do {
                    let settings = sharedModel.settings
                    var results: [ImageCompressResult] = []
                    for model in models {
                        guard model.isSupported else {
                            throw ImageCompressError.unsupportedFormat(model.inputURL.pathExtension.lowercased())
                        }
                        results.append(try await ImageCompressFFmpegRunner.run(
                            inputURL: model.inputURL,
                            quality: settings.quality,
                            stripsMetadata: settings.stripsMetadata,
                            pngCompressionLevel: settings.pngCompressionLevel,
                            fps: model.supportsFPS ? settings.fps : nil
                        ))
                    }
                    return results
                } catch {
                    sharedModel.errorMessage = error.localizedDescription
                    return nil
                }
            } reveal: { outputURLs in
                NSWorkspace.shared.activateFileViewerSelecting(outputURLs)
            } resizeWindow: { [weak self] width, duration in
                self?.panel.animateWidth(to: width, duration: duration)
            }
            .frame(height: size.height)
        )
    }

    func hide() {
        panel.hide()
    }
}
