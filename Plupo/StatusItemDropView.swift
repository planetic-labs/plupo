import AppKit

final class StatusItemDropView: NSView {
    private static let supportedTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .png, .tiff, .string]

    private weak var button: NSStatusBarButton?
    private let onDrop: ([NSItemProvider]) -> Bool

    init(button: NSStatusBarButton, onDrop: @escaping ([NSItemProvider]) -> Bool) {
        self.button = button
        self.onDrop = onDrop
        super.init(frame: button.bounds)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes(Self.supportedTypes)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        button?.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        button?.rightMouseDown(with: event)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !(sender.draggingSource is NativeDragSource.DragView),
              sender.draggingSourceOperationMask.contains(.copy),
              sender.draggingPasteboard.availableType(from: Self.supportedTypes) != nil else { return [] }
        button?.highlight(true)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        button?.highlight(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        button?.highlight(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { button?.highlight(false) }
        return onDrop(Self.providers(from: sender.draggingPasteboard))
    }

    static func providers(from pasteboard: NSPasteboard) -> [NSItemProvider] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            let provider = NSItemProvider()
            for type in supportedTypes {
                guard let data = item.data(forType: type) else { continue }
                // Snapshot the representation while the drag pasteboard is still valid.
                provider.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
            }
            return provider.registeredTypeIdentifiers.isEmpty ? nil : provider
        }
    }
}
