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
        private var selectsOnMouseUp = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            guard let id = item?.id, let viewModel else { return }
            let extending = event.modifierFlags.contains(.command)
            selectsOnMouseUp = !extending && viewModel.selectedIDs.contains(id)
            if !selectsOnMouseUp { viewModel.select(id, extending: extending) }
            if event.clickCount == 2 { preview?() }
        }

        override func mouseUp(with event: NSEvent) {
            if mouseDownPoint != nil, selectsOnMouseUp, let id = item?.id {
                viewModel?.select(id, extending: false)
            }
            mouseDownPoint = nil
            selectsOnMouseUp = false
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
            context == .outsideApplication ? .copy : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            viewModel?.finishDrag(itemIDs: draggedIDs, operation: operation,
                                  keepItems: PreferencesStore.shared.keepItemsAfterDrag)
            draggedIDs.removeAll()
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
