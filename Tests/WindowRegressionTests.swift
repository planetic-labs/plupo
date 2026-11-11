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
        let screenshotFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: screenshotFolder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: screenshotFolder) }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aB9sAAAAASUVORK5CYII=")!
        func writeScreenshot(_ name: String) throws {
            let url = screenshotFolder.appendingPathComponent(name)
            try png.write(to: url)
            let tag = Data([1])
            let result = tag.withUnsafeBytes {
                setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, $0.count, 0, 0)
            }
            expect(result == 0, "The test screenshot must have the macOS capture attribute")
        }
        try writeScreenshot("Old screenshot.png")
        var imported: [ShelfItem] = []
        let monitor = ScreenshotMonitor { imported.append(contentsOf: $0) }
        defer { monitor.stop() }
        try monitor.start(in: screenshotFolder)
        try png.write(to: screenshotFolder.appendingPathComponent("Ordinary image.png"))
        try writeScreenshot("New screenshot.png")
        try await Task.sleep(for: .milliseconds(2400))
        expect(imported.map(\.title) == ["New screenshot.png"], "Import only new screenshots, once")
        expect(monitor.detectedScreenshot, "A successful import should confirm setup")
        monitor.stop()
        try writeScreenshot("While paused.png")
        try monitor.start(in: screenshotFolder)
        try await Task.sleep(for: .milliseconds(1300))
        expect(imported.count == 1, "Resuming should skip screenshots already present")
        manager.hideShelfWindow()
        print("Passed \(checks) window and menu regression checks")
    }
}
