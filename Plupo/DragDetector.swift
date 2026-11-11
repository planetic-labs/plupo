import Foundation
import AppKit

class DragDetector {
    static let shared = DragDetector()

    private var monitor: Timer?
    private var lastDragChangeCount = -1
    private var mousePressLocation: NSPoint?
    private var isDraggingActive = false

    private init() {}

    func startMonitoring() {
        stopMonitoring()
        lastDragChangeCount = NSPasteboard(name: .drag).changeCount

        // Dock stacks can take over mouse tracking before the drag pasteboard is ready.
        // Sample independently of mouse-drag events, including during AppKit tracking.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDrag() }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitor = timer
    }

    func stopMonitoring() {
        monitor?.invalidate()
        monitor = nil
        if mousePressLocation != nil { WindowManager.shared.disarmDragEdge() }
        mousePressLocation = nil
        endDrag()
    }

    private func checkDrag() {
        let isMousePressed = NSEvent.pressedMouseButtons & 1 != 0
        if !isMousePressed {
            guard mousePressLocation != nil else { return }
            mousePressLocation = nil
            lastDragChangeCount = NSPasteboard(name: .drag).changeCount
            WindowManager.shared.disarmDragEdge()
            endDrag()
            return
        }

        let location = NSEvent.mouseLocation
        let origin = mousePressLocation ?? location
        mousePressLocation = origin
        guard !isDraggingActive else { return }
        if hypot(location.x - origin.x, location.y - origin.y) >= 4 {
            WindowManager.shared.armDragEdge()
        }
        let pasteboard = NSPasteboard(name: .drag)
        let changeCount = pasteboard.changeCount
        guard changeCount != lastDragChangeCount,
              pasteboard.pasteboardItems?.isEmpty == false else { return }
        lastDragChangeCount = changeCount
        beginDrag()
    }

    func beginDrag() {
        guard monitor != nil, !isDraggingActive else { return }
        isDraggingActive = true
        WindowManager.shared.disarmDragEdge()
        WindowManager.shared.dragDidBegin()
    }

    private func endDrag() {
        guard isDraggingActive else { return }
        isDraggingActive = false
        WindowManager.shared.dragDidEnd()
    }
}
