import SwiftUI
import AppKit

// A real AppKit drag source reports whether the destination accepted the drop.
struct NativeDragSource: NSViewRepresentable {
    let item: ShelfItem
    let viewModel: ShelfViewModel
    var stack: ShelfViewModel.Stack? = nil
    let preview: () -> Void

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        view.item = item
        view.viewModel = viewModel
        view.preview = preview
        view.stack = stack
    }

    class DragView: NSView, NSDraggingSource {
        var item: ShelfItem?
        var stack: ShelfViewModel.Stack?
        weak var viewModel: ShelfViewModel?
        var preview: (() -> Void)?
        private var mouseDownPoint: NSPoint?
        private var draggedIDs = Set<UUID>()
        private var extendsSelection = false
        private var canMoveOriginals = false
        private var fileReferences: [UUID: NSURL] = [:]

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            if stack != nil {
                if event.clickCount == 2 { preview?() }
                return
            }
            guard let id = item?.id, let viewModel else { return }
            extendsSelection = event.modifierFlags.contains(.command)
            if !extendsSelection && !viewModel.selectedIDs.contains(id) {
                viewModel.select(id, extending: false)
            }
            if event.clickCount == 2 { preview?() }
        }

        override func mouseUp(with event: NSEvent) {
            if stack == nil, mouseDownPoint != nil, let id = item?.id {
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
            let candidates = stack.map { viewModel.stackItems($0) } ?? viewModel.itemsForDrag(startingAt: item.id)
            let payload = candidates.compactMap { candidate in
                candidate.pasteboardWriter().map { (candidate, $0) }
            }
            guard !payload.isEmpty else { return }
            mouseDownPoint = nil
            draggedIDs = Set(payload.map { $0.0.id })
            let temporaryDirectory = PlupoTemporaryFiles.directory.resolvingSymlinksInPath().path
            canMoveOriginals = payload.allSatisfy { entry in
                guard case .file(let url) = entry.0.content else { return false }
                return !url.resolvingSymlinksInPath().path.hasPrefix(temporaryDirectory + "/")
            }
            if canMoveOriginals {
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
            // AppKit filters the offered operations using the current modifier keys.
            return canMoveOriginals ? [.copy, .move] : .copy
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
            canMoveOriginals = false
            WindowManager.shared.dragDidEnd(source: "shelf")
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard let item else { return nil }
            let menu = NSMenu()
            if stack != nil {
                let entry = NSMenuItem(title: "Split Stack", action: #selector(splitStack), keyEquivalent: "")
                entry.target = self
                menu.addItem(entry)
                return menu
            }
            for (title, action) in [(item.isLocked ? "Unlock Item" : "Lock Item", #selector(toggleLock)),
                                    ("Quick Look", #selector(showPreview)), ("Remove", #selector(remove))] {
                let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
                entry.target = self
                menu.addItem(entry)
            }
            return menu
        }

        @objc private func splitStack() { if let stack { viewModel?.splitStack(stack.id) } }
        @objc private func toggleLock() { if let item { viewModel?.toggleLock(for: item) } }
        @objc private func showPreview() { preview?() }
        @objc private func remove() { if let item { viewModel?.removeItem(item) } }
    }
}
