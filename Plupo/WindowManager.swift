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
    private var needsUpdate = false
    private var visibility = ShelfVisibilityState()
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
            self.visibility.apply(mode: mode)
            self.updateShelfPosition()
        }.store(in: &subscriptions)
        PreferencesStore.shared.$position.combineLatest(PreferencesStore.shared.$alignment)
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
        guard visibility.canAutoHide else { return }
        let generation = hideGeneration
        let task = DispatchWorkItem { [weak self] in
            guard let self, generation == self.hideGeneration else { return }
            self.refreshVisibilityInputs()
            guard self.visibility.canAutoHide else { return }
            self.hideShelfWindow()
        }
        autoHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    func armDragEdge() {
        guard visibility.mode == .dragStarts, !visibility.desiredVisible else {
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

    func dragDidBegin(source: String = "monitor") {
        cancelAutoHide()
        visibility.dragSources.insert(source)
        if visibility.mode == .dragStarts { showShelfWindow() }
    }

    func dragDidEnd(source: String = "monitor") {
        visibility.dragSources.remove(source)
        scheduleAutoHide()
    }

    func addScreenshots(_ screenshots: [ShelfItem]) {
        shelfViewModel.addItems(screenshots)
        showShelfWindow()
    }

    func showShelfWindow() {
        cancelAutoHide()
        visibility.desiredVisible = true
        updateShelfPosition()
    }

    func hideShelfWindow() {
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
    
    private func updateShelfPosition() {
        if isAnimating {
            needsUpdate = true
            return
        }
        if visibility.desiredVisible && shelfPanel == nil { createShelfPanel() }
        guard let panel = shelfPanel else { return }
        let target = getTargetFrame(for: getActiveScreen(), isVisibleState: visibility.desiredVisible)
        let alpha: CGFloat = visibility.desiredVisible ? 1 : 0
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
        var y: CGFloat = 0
        
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
        
        // Calculate Y Position
        switch prefs.alignment {
        case .top:
            y = screenFrame.maxY - windowHeight - 20
        case .center:
            y = screenFrame.minY + (screenFrame.height - windowHeight) / 2
        case .bottom:
            y = screenFrame.minY + 20
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
        
        // Switch to regular app temporarily so preferences window has a menu bar and behaves properly
        NSApp.setActivationPolicy(.regular)
        
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
        window.delegate = self
        
        let prefsView = PreferencesView()
            .environmentObject(PreferencesStore.shared)
        
        window.contentView = NSHostingView(rootView: prefsView)
        self.preferencesWindow = window
    }
}

// Keep application working in accessory mode when preferences close
extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == preferencesWindow {
            // Switch back to accessory (background/menu-bar only) mode
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private final class DragEdgeView: NSView {
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // Wait until AppKit finishes dispatching the entry before replacing the destination.
        DispatchQueue.main.async {
            guard NSEvent.pressedMouseButtons & 1 != 0 else { return }
            DragDetector.shared.beginDrag()
        }
        return []
    }
}
