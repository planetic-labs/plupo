import SwiftUI
import AppKit
import Combine

@main
struct PlupoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // We don't use the default WindowGroup scene because we manage our windows customly
        // via WindowManager (NSPanel for Shelf, NSWindow for Preferences).
        // Settings scene keeps Xcode happy and prevents default window spawn.
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var statusItem: NSStatusItem?
    private lazy var savedShelf = ShelfPersistence(model: WindowManager.shared.shelfViewModel)
    private var menuShortcutSubscription: AnyCancellable?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        PlupoTemporaryFiles.cleanup()

        // Set app as accessory (hides from Dock, acts as background agent)
        NSApp.setActivationPolicy(.accessory)
        
        // Start monitoring system drag events
        DragDetector.shared.startMonitoring()
        
        // Setup Menu Bar Icon
        setupStatusItem()
        
        // Initialize visibility subscriptions, including the saved mode.
        _ = WindowManager.shared
        _ = savedShelf
        ShelfShortcut.shared.start()
        ScreenshotMonitor.shared.restore()
        ScreenshotMonitor.downloads.restore()
        UpdateChecker.shared.start()
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        _ = savedShelf
        WindowManager.shared.addOpenedFiles(urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        savedShelf.close()
        ShelfShortcut.shared.stop()
        ScreenshotMonitor.downloads.stop()
        ScreenshotMonitor.shared.stop()
        DragDetector.shared.stopMonitoring()
        PlupoTemporaryFiles.cleanup()
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Plupo")
            button.addSubview(StatusItemDropView(button: button) { providers in
                WindowManager.shared.shelfViewModel.handleDroppedProviders(providers)
            })
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Shelf", action: #selector(toggleShelf), keyEquivalent: "y"))
        menu.addItem(NSMenuItem(title: "Add from Clipboard", action: #selector(addFromClipboard), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Restore Last Removed", action: #selector(restoreLastRemoved), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Remember Shelf Between Launches", action: #selector(toggleSavedShelf), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Plupo", action: #selector(quitApp), keyEquivalent: "q"))
        
        for item in menu.items where !item.isSeparatorItem { item.target = self }
        statusItem?.menu = menu
        let shortcuts = ShelfShortcut.shared
        menuShortcutSubscription = shortcuts.$menuShortcuts.combineLatest(shortcuts.$disabledMenuShortcuts)
            .sink { [weak menu] overrides, disabled in
                let actions: [(MenuShortcutAction, Selector)] = [
                    (.toggleShelf, #selector(AppDelegate.toggleShelf)),
                    (.preferences, #selector(AppDelegate.showPreferences)),
                    (.quit, #selector(AppDelegate.quitApp))
                ]
                for (action, selector) in actions {
                    guard let item = menu?.items.first(where: { $0.action == selector }) else { continue }
                    let custom = overrides[action.rawValue]
                    item.keyEquivalent = disabled.contains(action.rawValue) ? "" : (custom?.character ?? action.defaultKey)
                    item.keyEquivalentModifierMask = custom?.appKitModifiers ?? .command
                }
            }
    }
    
    @objc func toggleShelf() {
        WindowManager.shared.toggleShelfWindow()
    }
    
    @objc func addFromClipboard() {
        if !WindowManager.shared.addFromClipboard() {
            let alert = NSAlert()
            alert.messageText = "No supported items in the clipboard"
            alert.informativeText = "Copy a file, link, image, or plain text and try again."
            alert.runModal()
        }
    }

    @objc private func toggleSavedShelf() {
        do {
            try savedShelf.setEnabled(!savedShelf.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not remove the saved shelf"
            alert.informativeText = "Shelf saving is still enabled."
            alert.runModal()
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSavedShelf) {
            menuItem.state = savedShelf.isEnabled ? .on : .off
        }
        if menuItem.action == #selector(restoreLastRemoved) {
            return WindowManager.shared.shelfViewModel.canRestoreLastRemoved
        }
        return true
    }

    @objc func restoreLastRemoved() {
        let manager = WindowManager.shared
        if manager.shelfViewModel.restoreLastRemoved() { manager.showShelfWindow() }
    }

    @objc func showPreferences() {
        WindowManager.shared.showPreferencesWindow()
    }
    
    @objc func checkForUpdates() {
        UpdateChecker.shared.check()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
