import Foundation
import AppKit

class DragDetector {
    static let shared = DragDetector()

    private var monitor: Timer?
    private var lastDragChangeCount = -1
    private var mousePressLocation: NSPoint?
    private var isDraggingActive = false
    private var shake = DragShakeGesture()

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
        NotchDropTarget.shared.hide()
        if mousePressLocation != nil { WindowManager.shared.disarmDragEdge() }
        mousePressLocation = nil
        shake.reset()
        endDrag()
    }

    private func checkDrag() {
        let isMousePressed = NSEvent.pressedMouseButtons & 1 != 0
        if !isMousePressed {
            NotchDropTarget.shared.hide()
            guard mousePressLocation != nil else { return }
            mousePressLocation = nil
            shake.reset()
            lastDragChangeCount = NSPasteboard(name: .drag).changeCount
            WindowManager.shared.disarmDragEdge()
            endDrag()
            return
        }

        let location = NSEvent.mouseLocation
        let origin = mousePressLocation ?? location
        mousePressLocation = origin
        NotchDropTarget.shared.update(isDragging: isDraggingActive
            || hypot(location.x - origin.x, location.y - origin.y) >= 4)
        if isDraggingActive {
            if PreferencesStore.shared.showOnShake {
                if shake.sample(location, time: ProcessInfo.processInfo.systemUptime,
                                minimumDistance: PreferencesStore.shared.shakeSensitivity.minimumDistance) {
                    WindowManager.shared.dragDidShake()
                }
            } else {
                shake.reset()
            }
            return
        }
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
        shake.reset()
        WindowManager.shared.disarmDragEdge()
        WindowManager.shared.dragDidBegin()
    }

    private func endDrag() {
        guard isDraggingActive else { return }
        isDraggingActive = false
        WindowManager.shared.dragDidEnd()
    }
}


// Detect several deliberate reversals on either axis within a short time window.
struct DragShakeGesture {
    private var anchor: NSPoint?
    private var direction = NSPoint.zero
    private var reversals: [TimeInterval] = []

    mutating func reset() {
        self = DragShakeGesture()
    }

    mutating func sample(_ point: NSPoint, time: TimeInterval, minimumDistance: CGFloat = 18) -> Bool {
        guard let anchor else {
            self.anchor = point
            return false
        }
        let delta = NSPoint(x: point.x - anchor.x, y: point.y - anchor.y)
        guard max(abs(delta.x), abs(delta.y)) >= minimumDistance else { return false }
        let next = abs(delta.x) >= abs(delta.y)
            ? NSPoint(x: delta.x > 0 ? 1 : -1, y: 0)
            : NSPoint(x: 0, y: delta.y > 0 ? 1 : -1)
        reversals.removeAll { time - $0 > 0.7 }
        if next.x * direction.x + next.y * direction.y < 0 {
            reversals.append(time)
        }
        self.anchor = point
        direction = next
        guard reversals.count >= 3 else { return false }
        reset()
        return true
    }
}
