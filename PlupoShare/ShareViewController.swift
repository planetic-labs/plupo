import AppKit
import OSLog
import UniformTypeIdentifiers

final class ShareViewController: NSViewController {
    private let logger = Logger(subsystem: "org.plupo.Plupo", category: "Share")
    private var request: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var finished = false

    override func loadView() {
        let frame = NSRect(x: 0, y: 0, width: 300, height: 72)
        let content = NSView(frame: frame)
        let label = NSTextField(labelWithString: "Adding files to Plupo…")
        label.frame = frame.insetBy(dx: 20, dy: 20)
        label.alignment = .center
        label.autoresizingMask = [.width, .height]
        content.addSubview(label)
        view = content
        preferredContentSize = frame.size
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard request == nil, !finished, let context = extensionContext else { return }
        let providers = context.inputItems.compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) }
            catch { return }
            self?.finish(error: URLError(.timedOut))
        }
        request = Task { [weak self] in
            guard let self else { return }
            do {
                var files: [URL] = []
                for provider in providers {
                    files.append(try await fileURL(from: provider))
                    try Task.checkCancellation()
                }
                guard !files.isEmpty else { throw CocoaError(.fileReadUnsupportedScheme) }

                let app = Bundle(for: Self.self).bundleURL
                    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                let access = files.filter { $0.startAccessingSecurityScopedResource() }
                defer { access.forEach { $0.stopAccessingSecurityScopedResource() } }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try await NSWorkspace.shared.open(files, withApplicationAt: app, configuration: configuration)
                finish()
            } catch {
                finish(error: error)
            }
        }
    }

    private func finish(error: Error? = nil) {
        guard !finished else { return }
        finished = true
        deadline?.cancel()
        request?.cancel()
        if let error {
            logger.error("Share request failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code)")
            extensionContext?.cancelRequest(withError: error)
        } else {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func fileURL(from provider: NSItemProvider) async throws -> URL {
        let value = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil)
        if let url = value as? URL, url.isFileURL { return url }
        if let data = value as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL { return url }
        throw CocoaError(.fileReadUnsupportedScheme)
    }
}
