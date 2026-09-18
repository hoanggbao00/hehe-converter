import AppKit
import SwiftUI

@MainActor
final class ImageOCRResultWindowController: NSObject, NSWindowDelegate {
    private var windowController: NSWindowController?
    private var model: ImageOCRResultModel?

    func show(inputURLs: [URL]) {
        let model = ImageOCRResultModel(inputURLs: inputURLs)
        self.model = model

        let window = NSWindow(contentViewController: NSHostingController(rootView: ImageOCRResultView(model: model)))
        window.title = "OCR Result"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 460))
        window.contentMinSize = NSSize(width: 460, height: 300)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        windowController = NSWindowController(window: window)
        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)

        Task { await model.recognize() }
    }

    func windowWillClose(_ notification: Notification) {
        windowController = nil
        model = nil
    }
}

@MainActor
final class ImageOCRResultModel: ObservableObject {
    @Published var text = "Recognizing text..."
    @Published var isRecognizing = true

    private let inputURLs: [URL]

    init(inputURLs: [URL]) {
        self.inputURLs = inputURLs
    }

    func recognize() async {
        defer { isRecognizing = false }
        do {
            text = try await ImageOCRRunner.recognize(inputURLs: inputURLs)
        } catch {
            text = error.localizedDescription
        }
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct ImageOCRResultView: View {
    @ObservedObject var model: ImageOCRResultModel

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $model.text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .disabled(model.isRecognizing)

            Divider()

            HStack(spacing: 10) {
                if model.isRecognizing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Recognizing")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    model.copyAll()
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .disabled(model.isRecognizing || model.text.isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: 460, minHeight: 300)
    }
}

#Preview("OCR Result") {
    ImageOCRResultView(model: ImageOCRResultModel(inputURLs: []))
}
