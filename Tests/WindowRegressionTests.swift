import AppKit

@main
struct WindowRegressionTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let preferences = PreferencesStore.shared
        let originalMode = preferences.showBehavior
        defer { preferences.showBehavior = originalMode }
        preferences.showBehavior = .shortcut
        let manager = WindowManager.shared
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard value() else { fatalError(message) }
        }
        func settle() async throws { try await Task.sleep(for: .milliseconds(800)) }
        manager.showShelfWindow()
        manager.hideShelfWindow() // Deliberately request hiding during the opening animation.
        try await settle()
        let panel = NSApp.windows.compactMap { $0 as? NSPanel }.first!
        expect(panel.alphaValue == 0, "Hide during show animation must eventually hide")
        manager.showShelfWindow()
        manager.hideShelfWindow()
        manager.showShelfWindow()
        try await settle()
        expect(panel.alphaValue == 1, "The last request must win after rapid toggles")
        manager.hideShelfWindow()
        preferences.showBehavior = .always
        try await settle()
        expect(panel.alphaValue == 1, "Always Visible must apply to a hidden shelf immediately")
        expect(panel.frame.width == 64, "An empty shelf must open at its compact width")
        expect(manager.shelfViewModel.handleDroppedProviders([NSItemProvider(object: "width test" as NSString)]),
               "The shelf must accept the test drop")
        try await settle()
        expect(panel.frame.width == 150, "Adding the first item must expand the shelf")
        manager.shelfViewModel.clearAll()
        try await settle()
        expect(panel.frame.width == 64, "Removing the last item must restore the compact width")
        preferences.showBehavior = .dragStarts
        manager.showShelfWindow()
        manager.dragDidEnd() // Schedule hiding an empty shelf.
        preferences.showBehavior = .always
        try await settle()
        expect(panel.alphaValue == 1, "An old hide timer must not override Always Visible")
        preferences.showBehavior = .dragStarts
        manager.showShelfWindow()
        manager.dragDidEnd()
        manager.dragDidBegin(source: "regression")
        try await settle()
        expect(panel.alphaValue == 1, "A new drag must cancel the old hide timer")
        manager.dragDidEnd(source: "regression")
        try await settle()
        expect(panel.alphaValue == 0, "An empty shelf should hide when the final drag ends")

        let model = ShelfViewModel()
        let item = ShelfItem(content: .text("menu test"))
        // The native context menu uses one toggle action for both labels.
        let view = NativeDragSource.DragView()
        view.item = item
        view.viewModel = model
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        expect(view.menu(for: event)?.items.first?.title == "Lock Item", "Unlocked menu label must offer locking")
        var locked = item
        locked.isLocked = true
        view.item = locked
        let menu = view.menu(for: event)!
        expect(menu.items.first?.title == "Unlock Item", "Locked menu label must offer unlocking")
        expect(menu.items.first?.action == NSSelectorFromString("toggleLock"), "Unlock must invoke the real toggle action")
        manager.hideShelfWindow()
        print("Passed \(checks) window and menu regression checks")
    }
}
