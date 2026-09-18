import AppKit
import SwiftUI

@MainActor
final class ImageResizeWindowController {
    private let panel = OverlayPanelController()

    func show(inputURLs: [URL], near mouseLocation: NSPoint, defaultScope: ResizeApplyScope) {
        let models = inputURLs.map(ImageResizeModel.init(inputURL:))
        guard !models.isEmpty else { return }
        let sharedModel = models[0]
        let height = ImageResizeView.panelHeight + (models.count > 1 ? 35 : 0)
        let width = models.count > 1 && defaultScope == .each
            ? ImageResizeView.multiColumnWidth * CGFloat(min(models.count, 3))
            : ImageResizeView.singleWidth
        let size = NSSize(width: width, height: height)
        panel.show(
            size: size,
            near: mouseLocation,
            content: ImageResizeView(
                models: models,
                sharedModel: sharedModel,
                defaultScope: defaultScope
            ) { [weak self] in
                self?.hide()
            } apply: { model in
                do {
                    return try await model.applyResize()
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
                    var outputURLs: [URL] = []
                    for model in models {
                        await model.loadImage()
                        let outputSize = ImageResizeModel.outputPixelSize(
                            for: model.pixelSize,
                            settings: settings
                        )
                        outputURLs.append(try await ImageResizeFFmpegRunner.run(
                            inputURL: model.inputURL,
                            outputPixelSize: outputSize
                        ))
                    }
                    return outputURLs
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
