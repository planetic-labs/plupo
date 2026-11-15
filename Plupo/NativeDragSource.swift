import SwiftUI
import AppKit

// A real AppKit drag source reports whether the destination accepted the drop.
struct NativeDragSource: NSViewRepresentable {
    let item: ShelfItem
    let viewModel: ShelfViewModel
    let preview: () -> Void

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        view.item = item
        view.viewModel = viewModel
        view.preview = preview
    }

    class DragView: NSView, NSDraggingSource {
        var item: ShelfItem?
        weak var viewModel: ShelfViewModel?
        var preview: (() -> Void)?
        private var mouseDownPoint: NSPoint?
        private var draggedIDs = Set<UUID>()
        private var extendsSelection = false
        private var requestsMove = false
        private var fileReferences: [UUID: NSURL] = [:]

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            guard let id = item?.id, let viewModel else { return }
            extendsSelection = event.modifierFlags.contains(.command)
            if !extendsSelection && !viewModel.selectedIDs.contains(id) {
                viewModel.select(id, extending: false)
            }
            if event.clickCount == 2 { preview?() }
        }

        override func mouseUp(with event: NSEvent) {
            if mouseDownPoint != nil, let id = item?.id {
                viewModel?.select(id, extending: extendsSelection)
            }
            mouseDownPoint = nil
            extendsSelection = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownPoint, let item else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard hypot(point.x - start.x, point.y - start.y) >= 4 else { return }
            guard let viewModel else { return }
            let payload = viewModel.itemsForDrag(startingAt: item.id).compactMap { candidate in
                candidate.pasteboardWriter().map { (candidate, $0) }
            }
            guard !payload.isEmpty else { return }
            mouseDownPoint = nil
            draggedIDs = Set(payload.map { $0.0.id })
            requestsMove = event.modifierFlags.contains(.command)
                && !event.modifierFlags.contains(.option)
                && payload.allSatisfy { entry in
                    guard case .file(let url) = entry.0.content else { return false }
                    let temporaryDirectory = PlupoTemporaryFiles.directory.resolvingSymlinksInPath().path
                    return !url.resolvingSymlinksInPath().path.hasPrefix(temporaryDirectory + "/")
                }
            if requestsMove {
                for (candidate, _) in payload {
                    if case .file(let url) = candidate.content,
                       let reference = (url as NSURL).fileReferenceURL() {
                        fileReferences[candidate.id] = reference as NSURL
                    }
                }
            }
            let draggingItems = payload.enumerated().map { index, entry in
                let draggingItem = NSDraggingItem(pasteboardWriter: entry.1)
                let offset = CGFloat(min(index, 3)) * 3
                draggingItem.setDraggingFrame(
                    NSRect(x: point.x - 16 + offset, y: point.y - 16 - offset, width: 32, height: 32),
                    contents: entry.0.thumbnail
                )
                return draggingItem
            }
            WindowManager.shared.dragDidBegin(source: "shelf")
            beginDraggingSession(with: draggingItems, event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // Reordering/duplicating items inside this shelf is not a supported operation.
            guard context == .outsideApplication else { return [] }
            return requestsMove ? [.copy, .move] : .copy
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            let keepItems = PreferencesStore.shared.keepItemsAfterDrag
            if operation.contains(.move) {
                viewModel?.finishFileMove(itemIDs: draggedIDs, references: fileReferences, keepItems: keepItems)
            } else {
                viewModel?.finishDrag(itemIDs: draggedIDs, operation: operation, keepItems: keepItems)
            }
            draggedIDs.removeAll()
            fileReferences.removeAll()
            requestsMove = false
            WindowManager.shared.dragDidEnd(source: "shelf")
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard let item else { return nil }
            let menu = NSMenu()
            for (title, action) in [(item.isLocked ? "Unlock Item" : "Lock Item", #selector(toggleLock)),
                                    ("Quick Look", #selector(showPreview)), ("Remove", #selector(remove))] {
                let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
                entry.target = self
                menu.addItem(entry)
            }
            return menu
        }

        @objc private func toggleLock() { if let item { viewModel?.toggleLock(for: item) } }
        @objc private func showPreview() { preview?() }
        @objc private func remove() { if let item { viewModel?.removeItem(item) } }
    }
}
