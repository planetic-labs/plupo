import AppKit

// Keep a reachable strip beneath the physical camera housing.
enum NotchDropGeometry {
    static func frame(screen: NSRect, topInset: CGFloat, left: NSRect?, right: NSRect?) -> NSRect? {
        guard topInset > 0, let left, let right,
              right.minX > left.maxX else { return nil }
        let width = right.minX - left.maxX
        guard width > 0, width < screen.width / 2 else { return nil }
        return NSRect(x: left.maxX - 8, y: screen.maxY - topInset - 28,
                      width: width + 16, height: topInset + 28)
    }
}

final class NotchDropTarget {
    static let shared = NotchDropTarget()
    private var panels: [NSPanel] = []
    private var frames: [NSRect] = []

    func update(isDragging: Bool) {
        guard isDragging, PreferencesStore.shared.dropToNotch else {
            hide()
            return
        }
        let targets = NSScreen.screens.compactMap {
            NotchDropGeometry.frame(screen: $0.frame, topInset: $0.safeAreaInsets.top,
                                    left: $0.auxiliaryTopLeftArea, right: $0.auxiliaryTopRightArea)
        }
        guard targets != frames else { return }
        hide()
        frames = targets
        for frame in targets {
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.contentView = NotchDropView()
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        frames.removeAll()
    }
}

private final class NotchDropView: NSView {
    private var highlighted = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .png, .tiff, .string])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: 0, y: 0, width: bounds.width, height: 28)
        (highlighted ? NSColor.controlAccentColor : NSColor.windowBackgroundColor)
            .withAlphaComponent(highlighted ? 0.85 : 0.9).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        let title = "Add to Plupo" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: highlighted ? NSColor.white : NSColor.labelColor
        ]
        let size = title.size(withAttributes: attributes)
        title.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (28 - size.height) / 2),
                   withAttributes: attributes)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !(sender.draggingSource is NativeDragSource.DragView),
              sender.draggingSourceOperationMask.contains(.copy),
              sender.draggingPasteboard.availableType(from: [.fileURL, .URL, .png, .tiff, .string]) != nil else {
            return []
        }
        highlighted = true
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { highlighted = false }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        highlighted = false
        let providers = StatusItemDropView.providers(from: sender.draggingPasteboard)
        return WindowManager.shared.shelfViewModel.handleDroppedProviders(providers)
    }
}
