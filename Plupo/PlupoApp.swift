import SwiftUI
import AppKit

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
        ShelfShortcut.shared.start()
        ScreenshotMonitor.shared.restore()
        ScreenshotMonitor.downloads.restore()
        UpdateChecker.shared.start()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Plupo", action: #selector(quitApp), keyEquivalent: "q"))
        
        for item in menu.items where !item.isSeparatorItem { item.target = self }
        statusItem?.menu = menu
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
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
