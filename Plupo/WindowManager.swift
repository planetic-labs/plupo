//
//  WindowManager.swift
//  Plupo
//
//  Created by Antigravity on 06.06.2026.
//

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

class WindowManager: NSObject {
    static let shared = WindowManager()
    
    let shelfViewModel = ShelfViewModel()
    
    private var shelfPanel: NSPanel?
    private var dragEdgePanel: NSPanel?
    private var preferencesWindow: NSWindow?
    
    private var windowWidth: CGFloat { shelfViewModel.usesCompactLayout ? 64 : 150 }
    private let windowHeight: CGFloat = 420
    private var isAnimating = false
    private var shelfMoveOffset: NSPoint?
    private let pointerShelfSize: CGFloat = 84
    private var pointerShelfOrigin: NSPoint? {
        didSet { shelfViewModel.isPointerDropTarget = pointerShelfOrigin != nil }
    }
    private var needsUpdate = false
    private var visibility = ShelfVisibilityState()
    private var fnShelfVisible = false
    private var subscriptions = Set<AnyCancellable>()
    private var autoHideTask: DispatchWorkItem?
    private var hideGeneration = 0
    
    private override init() {
        super.init()
        setupPreferencesObserver()
    }
    
    private func setupPreferencesObserver() {
        shelfViewModel.onItemsChanged = { [weak self] in
            self?.updateShelfPosition()
            self?.scheduleAutoHide()
        }
        shelfViewModel.onDropStarted = { [weak self] in self?.cancelAutoHide() }
        shelfViewModel.onDropFinished = { [weak self] in
            guard let self else { return }
            if !self.shelfViewModel.items.isEmpty || self.shelfViewModel.dropError != nil {
                self.showShelfWindow()
            }
        }
        PreferencesStore.shared.$showBehavior.removeDuplicates().sink { [weak self] mode in
            guard let self else { return }
            self.cancelAutoHide()
            self.refreshVisibilityInputs()
            self.pointerShelfOrigin = nil
            self.visibility.apply(mode: mode)
            self.updateShelfPosition()
        }.store(in: &subscriptions)
        PreferencesStore.shared.$position.removeDuplicates()
            .dropFirst().sink { [weak self] _ in
                // Published emits before the new value has been stored.
                DispatchQueue.main.async { self?.updateShelfPosition() }
            }.store(in: &subscriptions)
    }

    private func refreshVisibilityInputs() {
        visibility.itemCount = shelfViewModel.items.count
        visibility.isLoadingDrop = shelfViewModel.isLoadingDrop
        visibility.hasDropError = shelfViewModel.dropError != nil
    }

    private func cancelAutoHide() {
        hideGeneration += 1
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    private func scheduleAutoHide() {
        cancelAutoHide()
        refreshVisibilityInputs()
        guard canAutoHideShelf else { return }
        let generation = hideGeneration
        let task = DispatchWorkItem { [weak self] in
            guard let self, generation == self.hideGeneration else { return }
            self.refreshVisibilityInputs()
            guard self.canAutoHideShelf else { return }
            self.hideShelfWindow()
        }
        autoHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    private var canAutoHideShelf: Bool {
        visibility.canAutoHide || (pointerShelfOrigin != nil && visibility.dragSources.isEmpty
            && shelfViewModel.usesCompactLayout && !shelfViewModel.isLoadingDrop)
    }

    func armDragEdge() {
        guard visibility.mode == .dragStarts, PreferencesStore.shared.showNearScreenEdge, !visibility.desiredVisible else {
            disarmDragEdge()
            return
        }

        let screen = getActiveScreen()
        let target = getTargetFrame(for: screen, isVisibleState: true)
        let edgeWidth: CGFloat = 24
        let edgeX = PreferencesStore.shared.position == .left
            ? screen.visibleFrame.minX : screen.visibleFrame.maxX - edgeWidth
        let frame = NSRect(x: edgeX, y: target.minY, width: edgeWidth, height: target.height)

        let panel = dragEdgePanel ?? makeDragEdgePanel()
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func disarmDragEdge() {
        guard let panel = dragEdgePanel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func makeDragEdgePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        let destination = DragEdgeView()
        destination.registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png,
                                             NSPasteboard.PasteboardType(UTType.item.identifier)])
        panel.contentView = destination
        dragEdgePanel = panel
        return panel
    }

    func dragDidBegin(source: String = "monitor", allowAutomaticShow: Bool = true) {
        cancelAutoHide()
        visibility.dragSources.insert(source)
        if allowAutomaticShow && visibility.mode == .dragStarts && PreferencesStore.shared.showOnDragStart {
            showShelfWindow()
        }
    }

    func dragDidReachScreenEdge() {
        guard pointerShelfOrigin == nil, visibility.mode == .dragStarts,
              PreferencesStore.shared.showNearScreenEdge else { return }
        disarmDragEdge()
        showShelfWindow()
    }

    func dragDidShake() {
        let prefs = PreferencesStore.shared
        guard visibility.mode == .dragStarts, prefs.showOnShake else { return }
        if prefs.showNearPointerOnShake {
            showDropShelfNearPointer()
        } else {
            showShelfWindow()
        }
    }

    func showDropShelfNearPointer() {
        guard pointerShelfOrigin == nil else { return }
        guard visibility.mode != .always, shelfViewModel.usesCompactLayout, !shelfViewModel.isLoadingDrop else {
            showShelfWindow()
            return
        }
        let pointer = NSEvent.mouseLocation
        let visible = getActiveScreen().visibleFrame
        let x = max(visible.minX, min(pointer.x - pointerShelfSize / 2, visible.maxX - pointerShelfSize))
        let below = pointer.y - pointerShelfSize - 16
        let preferredY = below < visible.minY ? pointer.y + 16 : below
        let y = max(visible.minY, min(preferredY, visible.maxY - pointerShelfSize))
        pointerShelfOrigin = NSPoint(x: x, y: y)
        disarmDragEdge()
        cancelAutoHide()
        visibility.desiredVisible = true
        updateShelfPosition()
    }

    func dragDidEnd(source: String = "monitor") {
        visibility.dragSources.remove(source)
        scheduleAutoHide()
    }

    @discardableResult
    func addFromClipboard() -> Bool {
        guard shelfViewModel.importClipboard(.general) else { return false }
        showShelfWindow()
        return true
    }

    func addOpenedFiles(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        shelfViewModel.addItems(files.map { ShelfItem(content: .file($0)) })
        showShelfWindow()
    }

    func addMonitoredItems(_ items: [ShelfItem]) {
        shelfViewModel.addItems(items)
        showShelfWindow()
    }

    func showShelfWindow() {
        pointerShelfOrigin = nil
        cancelAutoHide()
        visibility.desiredVisible = true
        updateShelfPosition()
    }

    func hideShelfWindow() {
        pointerShelfOrigin = nil
        cancelAutoHide()
        visibility.desiredVisible = false
        updateShelfPosition()
    }

    func toggleShelfWindow() {
        visibility.desiredVisible ? hideShelfWindow() : showShelfWindow()
    }

    private func createShelfPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        
        // Host the SwiftUI View inside the panel
        let shelfView = ShelfView(viewModel: shelfViewModel)
            .environmentObject(PreferencesStore.shared)
        
        let hostingView = NSHostingView(rootView: shelfView)
        hostingView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        panel.contentView = hostingView
        
        self.shelfPanel = panel
        
        // Position it hidden initially and show it immediately to avoid reentrant drag logs later
        let screen = getActiveScreen()
        let hiddenFrame = getTargetFrame(for: screen, isVisibleState: false)
        panel.setFrame(hiddenFrame, display: true)
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
    }
    
    func setFnShelfVisible(_ visible: Bool) {
        guard fnShelfVisible != visible else { return }
        fnShelfVisible = visible
        updateShelfPosition()
    }

    func moveShelfWithPointer() {
        guard let panel = shelfPanel, !isAnimating else { return }
        let pointer = NSEvent.mouseLocation
        let offset = shelfMoveOffset ?? NSPoint(x: pointer.x - panel.frame.minX,
                                                y: pointer.y - panel.frame.minY)
        shelfMoveOffset = offset
        panel.setFrameOrigin(NSPoint(x: pointer.x - offset.x, y: pointer.y - offset.y))
    }

    func finishMovingShelf() {
        guard shelfMoveOffset != nil, let panel = shelfPanel else { return }
        defer {
            shelfMoveOffset = nil
            updateShelfPosition()
        }

        moveShelfWithPointer()
        let screen = getActiveScreen().visibleFrame
        let prefs = PreferencesStore.shared
        prefs.position = panel.frame.midX < screen.midX ? .left : .right
        prefs.shelfVerticalOffset = panel.frame.midY - screen.midY
    }

    private func updateShelfPosition() {
        guard shelfMoveOffset == nil else { return }
        if isAnimating {
            needsUpdate = true
            return
        }
        let showPanel = visibility.desiredVisible || fnShelfVisible
        if showPanel && shelfPanel == nil { createShelfPanel() }
        guard let panel = shelfPanel else { return }
        var target = getTargetFrame(for: getActiveScreen(), isVisibleState: showPanel)
        if showPanel, let pointerShelfOrigin {
            target = NSRect(origin: pointerShelfOrigin, size: NSSize(width: pointerShelfSize, height: pointerShelfSize))
            if panel.alphaValue == 0 { panel.setFrame(target, display: false) }
        }
        let alpha: CGFloat = showPanel ? 1 : 0
        guard panel.frame != target || panel.alphaValue != alpha else { return }
        isAnimating = true
        needsUpdate = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = alpha
        }, completionHandler: {
            self.isAnimating = false
            if self.needsUpdate { self.updateShelfPosition() }
        })
    }

    // Calculates the window frame based on active screen and settings
    private func getTargetFrame(for screen: NSScreen, isVisibleState: Bool) -> NSRect {
        let prefs = PreferencesStore.shared
        let screenFrame = screen.visibleFrame
        
        var x: CGFloat = 0
        let y: CGFloat
        
        // Calculate X Position
        if prefs.position == .left {
            if isVisibleState {
                x = screenFrame.minX + 8
            } else {
                x = screenFrame.minX - windowWidth - 20
            }
        } else { // Right
            if isVisibleState {
                x = screenFrame.maxX - windowWidth - 8
            } else {
                x = screenFrame.maxX + 20
            }
        }
        
        if let offset = prefs.shelfVerticalOffset {
            let origin = screenFrame.midY - windowHeight / 2 + offset
            y = max(screenFrame.minY, min(origin, screenFrame.maxY - windowHeight))
        } else {
            switch prefs.legacyAlignment {
            case .top: y = screenFrame.maxY - windowHeight - 20
            case .center: y = screenFrame.midY - windowHeight / 2
            case .bottom: y = screenFrame.minY + 20
            }
        }

        return NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
    }
    
    private func getActiveScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        
        // 1. Try to find the screen that directly contains the mouse cursor
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }
        
        // 2. If the mouse is slightly outside of all screens (e.g. during a drag near boundaries),
        // find the screen that is closest to the mouse cursor.
        if let closestScreen = NSScreen.screens.min(by: { 
            let dist0 = distance(from: mouseLocation, to: $0.frame)
            let dist1 = distance(from: mouseLocation, to: $1.frame)
            return dist0 < dist1
        }) {
            return closestScreen
        }
        
        // 3. Absolute fallbacks
        return NSScreen.main
            ?? NSScreen.screens.first
            ?? NSScreen()
    }
    
    private func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(0, max(rect.minX - point.x, point.x - rect.maxX))
        let dy = max(0, max(rect.minY - point.y, point.y - rect.maxY))
        return sqrt(dx * dx + dy * dy)
    }
    
    // MARK: - Preferences Window management
    
    func showPreferencesWindow() {
        if preferencesWindow == nil {
            createPreferencesWindow()
        }
        
        preferencesWindow?.center()
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func createPreferencesWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Plupo Preferences"
        window.isReleasedWhenClosed = false
        
        let prefsView = PreferencesView()
            .environmentObject(PreferencesStore.shared)
        
        window.contentView = NSHostingView(rootView: prefsView)
        self.preferencesWindow = window
    }
}

private final class DragEdgeView: NSView {
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // Wait until AppKit finishes dispatching the entry before replacing the destination.
        DispatchQueue.main.async {
            guard NSEvent.pressedMouseButtons & 1 != 0 else { return }
            DragDetector.shared.reachedScreenEdge()
        }
        return []
    }
}
