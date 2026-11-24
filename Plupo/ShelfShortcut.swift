import AppKit
import Carbon
import Combine
import Foundation

struct RecordedShortcut: Codable, Equatable {
    let key: UInt32
    let modifiers: UInt32
    let character: String
    let title: String

    var appKitModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    static func record() -> Self? {
        let dialog = NSAlert()
        dialog.messageText = "Press a keyboard shortcut"
        dialog.informativeText = "Press a key with Command or Control, or press a function key. Escape cancels."
        dialog.addButton(withTitle: "Cancel")
        var result: Self?
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { () -> Void in
                if event.keyCode == kVK_Escape {
                    NSApp.abortModal()
                    return
                }
                let flags = event.modifierFlags
                let functionNumber = event.specialKey.flatMap {
                    (0xF704...0xF726).contains($0.rawValue) ? $0.rawValue - 0xF703 : nil
                }
                guard flags.contains(.command) || flags.contains(.control) || functionNumber != nil else {
                    NSSound.beep()
                    return
                }
                var mask: Int = 0
                var label = ""
                for (flag, bit, symbol): (NSEvent.ModifierFlags, Int, String) in [
                    (.control, controlKey, "⌃"), (.option, optionKey, "⌥"),
                    (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")
                ] where flags.contains(flag) {
                    mask |= bit
                    label += symbol
                }
                guard let character = event.charactersIgnoringModifiers, !character.isEmpty else { return }
                let keyTitle = functionNumber.map { "F\($0)" } ?? (character == " " ? "Space" : character.uppercased())
                result = Self(key: UInt32(event.keyCode), modifiers: UInt32(mask),
                              character: character, title: label + keyTitle)
                NSApp.abortModal()
            }
            return nil
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
        dialog.runModal()
        return result
    }
}

enum ShelfShortcutChoice: String, CaseIterable, Identifiable {
    case disabled = "Off"
    case custom = "Custom"
    case yoink = "F5"
    case commandShiftY = "⌘⇧Y"
    case controlOptionY = "⌃⌥Y"
    case controlOptionSpace = "⌃⌥Space"
    case commandOptionJ = "⌘⌥J"

    var id: Self { self }

    var binding: (key: UInt32, modifiers: UInt32)? {
        switch self {
        case .disabled, .custom: return nil
        case .yoink: return (UInt32(kVK_F5), 0)
        case .commandShiftY: return (UInt32(kVK_ANSI_Y), UInt32(cmdKey | shiftKey))
        case .controlOptionY: return (UInt32(kVK_ANSI_Y), UInt32(controlKey | optionKey))
        case .controlOptionSpace: return (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .commandOptionJ: return (UInt32(kVK_ANSI_J), UInt32(cmdKey | optionKey))
        }
    }
}

enum ClipboardShortcutChoice: String, CaseIterable, Identifiable {
    case doubleF5 = "F5 twice (Yoink)"
    case dropover = "⌥⇧A (Dropover)"
    case controlOptionA = "⌃⌥A"
    case disabled = "Off"
    case custom = "Custom"

    var id: Self { self }

    var title: String {
        self == .doubleF5 ? "F5 twice" : rawValue
    }

    var binding: (key: UInt32, modifiers: UInt32)? {
        switch self {
        case .doubleF5: return ShelfShortcutChoice.yoink.binding
        case .dropover: return (UInt32(kVK_ANSI_A), UInt32(optionKey | shiftKey))
        case .controlOptionA: return (UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey))
        case .disabled, .custom: return nil
        }
    }
}

enum MenuShortcutAction: String, CaseIterable, Identifiable {
    case toggleShelf = "Toggle Shelf"
    case preferences = "Open Preferences"
    case quit = "Quit Plupo"

    var id: Self { self }

    var defaultKey: String {
        switch self {
        case .toggleShelf: return "y"
        case .preferences: return ","
        case .quit: return "q"
        }
    }
}

final class ShelfShortcut: ObservableObject {
    static let shared = ShelfShortcut()

    @Published private(set) var choice: ShelfShortcutChoice
    @Published private(set) var errorMessage: String?

    @Published private(set) var clipboardChoice: ClipboardShortcutChoice
    @Published private(set) var clipboardError: String?

    @Published private(set) var customShelf = ShelfShortcut.loadRecorded("customShelfShortcut")
    @Published private(set) var customClipboard = ShelfShortcut.loadRecorded("customClipboardShortcut")

    private static func loadRecorded(_ key: String) -> RecordedShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RecordedShortcut.self, from: data)
    }

    func recordCustom(clipboard: Bool) {
        guard let shortcut = RecordedShortcut.record() else { return }
        if clipboard {
            let previous = customClipboard
            customClipboard = shortcut
            applyClipboard(.custom, rollback: { customClipboard = previous })
            if clipboardError == nil {
                UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: "customClipboardShortcut")
            }
        } else {
            let previous = customShelf
            if choice == .custom, previous == shortcut, hotKey != nil { return }
            customShelf = shortcut
            apply(.custom, rebind: true)
            if errorMessage == nil {
                UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: "customShelfShortcut")
            } else {
                customShelf = previous
            }
        }
    }

    @Published var menuShortcuts: [String: RecordedShortcut] = {
        guard let data = UserDefaults.standard.data(forKey: "localMenuShortcuts") else { return [:] }
        return (try? JSONDecoder().decode([String: RecordedShortcut].self, from: data)) ?? [:]
    }() {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(menuShortcuts), forKey: "localMenuShortcuts")
        }
    }

    @Published var disabledMenuShortcuts = Set(UserDefaults.standard.stringArray(forKey: "disabledMenuShortcuts") ?? []) {
        didSet { UserDefaults.standard.set(Array(disabledMenuShortcuts), forKey: "disabledMenuShortcuts") }
    }

    func recordMenuShortcut(_ action: MenuShortcutAction) {
        guard let shortcut = RecordedShortcut.record() else { return }
        menuShortcuts[action.rawValue] = shortcut
        disabledMenuShortcuts.remove(action.rawValue)
    }

    private let clipboardPreferenceKey = "clipboardGlobalShortcut"
    private var clipboardHotKey: EventHotKeyRef?
    private var pendingF5: Task<Void, Never>?

    @Published var showShelfWhileHoldingFn = UserDefaults.standard.bool(forKey: "showShelfWhileHoldingFn") {
        didSet {
            UserDefaults.standard.set(showShelfWhileHoldingFn, forKey: "showShelfWhileHoldingFn")
            refreshFnMonitor()
        }
    }
    private var fnMonitor: Timer?

    private func refreshFnMonitor() {
        stopFnMonitor()
        guard showShelfWhileHoldingFn else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                WindowManager.shared.setFnShelfVisible(NSEvent.modifierFlags.contains(.function))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fnMonitor = timer
    }

    private func stopFnMonitor() {
        guard let fnMonitor else { return }
        fnMonitor.invalidate()
        self.fnMonitor = nil
        WindowManager.shared.setFnShelfVisible(false)
    }

    private let preferenceKey = "shelfGlobalShortcut"
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {
        choice = UserDefaults.standard.string(forKey: preferenceKey)
            .flatMap(ShelfShortcutChoice.init(rawValue:)) ?? .yoink
        clipboardChoice = UserDefaults.standard.string(forKey: clipboardPreferenceKey)
            .flatMap(ClipboardShortcutChoice.init(rawValue:)) ?? .doubleF5
    }

    func start() {
        refreshFnMonitor()
        apply(choice)
        refreshClipboardRegistration()
    }

    func apply(_ newChoice: ShelfShortcutChoice, rebind: Bool = false) {
        errorMessage = nil
        if !rebind, newChoice == choice, hotKey != nil { return }

        if newChoice == .yoink && clipboardChoice == .doubleF5 {
            unregisterClipboard()
        }
        var newHotKey: EventHotKeyRef?
        let customBinding = customShelf.map { (key: $0.key, modifiers: $0.modifiers) }
        if let binding = newChoice == .custom ? customBinding : newChoice.binding {
            guard installHandler() else {
                errorMessage = "Plupo couldn’t start keyboard shortcut handling."
                refreshClipboardRegistration()
                return
            }
            let id = EventHotKeyID(signature: 0x504C5550, id: 1)
            let status = RegisterEventHotKey(binding.key, binding.modifiers, id,
                                             GetApplicationEventTarget(), 0, &newHotKey)
            guard status == noErr, newHotKey != nil else {
                errorMessage = "This shortcut is unavailable. Choose a different one."
                refreshClipboardRegistration()
                return
            }
        }

        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = newHotKey
        choice = newChoice
        UserDefaults.standard.set(newChoice.rawValue, forKey: preferenceKey)
        refreshClipboardRegistration()
    }

    func applyClipboard(_ newChoice: ClipboardShortcutChoice, rollback: () -> Void = {}) {
        let previous = clipboardChoice
        clipboardChoice = newChoice
        refreshClipboardRegistration()
        if let failure = clipboardError {
            clipboardChoice = previous
            rollback()
            refreshClipboardRegistration()
            clipboardError = failure
        } else {
            UserDefaults.standard.set(newChoice.rawValue, forKey: clipboardPreferenceKey)
        }
    }

    private func unregisterClipboard() {
        pendingF5?.cancel()
        pendingF5 = nil
        if let clipboardHotKey { UnregisterEventHotKey(clipboardHotKey) }
        clipboardHotKey = nil
    }

    private func refreshClipboardRegistration() {
        unregisterClipboard()
        clipboardError = nil
        let customBinding = customClipboard.map { (key: $0.key, modifiers: $0.modifiers) }
        guard let binding = clipboardChoice == .custom ? customBinding : clipboardChoice.binding else { return }
        if clipboardChoice == .doubleF5, choice == .yoink, hotKey != nil { return }
        if clipboardChoice == .doubleF5, choice == .yoink {
            clipboardError = "F5 is unavailable. Choose another shortcut."
            return
        }
        let id = EventHotKeyID(signature: 0x504C5550, id: 2)
        guard installHandler(),
              RegisterEventHotKey(binding.key, binding.modifiers, id, GetApplicationEventTarget(), 0, &clipboardHotKey) == noErr,
              clipboardHotKey != nil else {
            if clipboardChoice == .dropover {
                clipboardError = "Option–Shift–A is unavailable. On macOS 15 or later, try Control–Option–A."
            } else {
                clipboardError = "This shortcut is unavailable. Choose a different one."
            }
            return
        }
    }

    private func handleHotKey(_ id: UInt32) {
        let togglesShelf = id == 1
        guard togglesShelf ? hotKey != nil : clipboardHotKey != nil else { return }
        let isF5 = togglesShelf ? choice == .yoink : clipboardChoice == .doubleF5
        guard isF5 && clipboardChoice == .doubleF5 else {
            if togglesShelf { WindowManager.shared.toggleShelfWindow() }
            else { WindowManager.shared.addFromClipboard() }
            return
        }
        if let pendingF5 {
            pendingF5.cancel()
            self.pendingF5 = nil
            WindowManager.shared.addFromClipboard()
        } else {
            pendingF5 = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(300)) }
                catch { return }
                guard let self else { return }
                self.pendingF5 = nil
                if togglesShelf { WindowManager.shared.toggleShelfWindow() }
            }
        }
    }

    func stop() {
        stopFnMonitor()
        unregisterClipboard()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    private func installHandler() -> Bool {
        if handler != nil { return true }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyReleased))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == 0x504C5550, (id.id == 1 || id.id == 2) else {
                return OSStatus(eventNotHandledErr)
            }
            let hotKeyID = id.id
            DispatchQueue.main.async {
                ShelfShortcut.shared.handleHotKey(hotKeyID)
            }
            return noErr
        }, 1, &event, nil, &handler)
        return status == noErr
    }
}
