import AppKit
import UniformTypeIdentifiers

final class ShareViewController: NSViewController {
    private let status = NSTextField(wrappingLabelWithString: "Add the selected files to the Plupo shelf.")
    private var shareTask: Task<Void, Never>?
    private lazy var addButton = NSButton(title: "Add to Plupo", target: self, action: #selector(addFiles))

    override func loadView() {
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelShare))
        cancel.keyEquivalent = "\u{1b}"
        addButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, addButton])
        buttons.alignment = .centerY

        let content = NSStackView(views: [status, buttons])
        content.orientation = .vertical
        content.alignment = .trailing
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false

        view = NSView()
        view.addSubview(content)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 320),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            status.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
        preferredContentSize = NSSize(width: 320, height: 130)
    }

    @objc private func addFiles() {
        guard let context = extensionContext else { return }
        let providers = context.inputItems.compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
        addButton.isEnabled = false
        status.stringValue = "Adding files…"
        shareTask = Task {
            do {
                var files: [URL] = []
                for provider in providers {
                    files.append(try await fileURL(from: provider))
                }
                try Task.checkCancellation()
                guard !files.isEmpty else { throw CocoaError(.fileReadUnsupportedScheme) }

                // Open the containing app through Launch Services with the original file URLs.
                let app = Bundle(for: Self.self).bundleURL
                    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                let access = files.filter { $0.startAccessingSecurityScopedResource() }
                defer { access.forEach { $0.stopAccessingSecurityScopedResource() } }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try await NSWorkspace.shared.open(files, withApplicationAt: app, configuration: configuration)
                context.completeRequest(returningItems: nil, completionHandler: nil)
            } catch is CancellationError {
                return
            } catch {
                status.stringValue = "Could not add the selected files to Plupo."
                addButton.isEnabled = true
            }
        }
    }

    private func fileURL(from provider: NSItemProvider) async throws -> URL {
        let value = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil)
        if let url = value as? URL, url.isFileURL { return url }
        if let data = value as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL { return url }
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    @objc private func cancelShare() {
        shareTask?.cancel()
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}
