import Carbon
import Combine
import Foundation

enum ShelfShortcutChoice: String, CaseIterable, Identifiable {
    case disabled = "Off"
    case commandShiftY = "⌘⇧Y"
    case controlOptionY = "⌃⌥Y"
    case controlOptionSpace = "⌃⌥Space"
    case commandOptionJ = "⌘⌥J"

    var id: Self { self }

    var binding: (key: UInt32, modifiers: UInt32)? {
        switch self {
        case .disabled: return nil
        case .commandShiftY: return (UInt32(kVK_ANSI_Y), UInt32(cmdKey | shiftKey))
        case .controlOptionY: return (UInt32(kVK_ANSI_Y), UInt32(controlKey | optionKey))
        case .controlOptionSpace: return (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .commandOptionJ: return (UInt32(kVK_ANSI_J), UInt32(cmdKey | optionKey))
        }
    }
}

final class ShelfShortcut: ObservableObject {
    static let shared = ShelfShortcut()

    @Published private(set) var choice: ShelfShortcutChoice
    @Published private(set) var errorMessage: String?

    private let preferenceKey = "shelfGlobalShortcut"
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {
        choice = UserDefaults.standard.string(forKey: preferenceKey)
            .flatMap(ShelfShortcutChoice.init(rawValue:)) ?? .disabled
    }

    func start() {
        apply(choice)
    }

    func apply(_ newChoice: ShelfShortcutChoice) {
        errorMessage = nil
        if newChoice == choice, hotKey != nil { return }

        var newHotKey: EventHotKeyRef?
        if let binding = newChoice.binding {
            guard installHandler() else {
                errorMessage = "Plupo couldn’t start keyboard shortcut handling."
                return
            }
            let id = EventHotKeyID(signature: 0x504C5550, id: 1)
            let status = RegisterEventHotKey(binding.key, binding.modifiers, id,
                                             GetApplicationEventTarget(), 0, &newHotKey)
            guard status == noErr, newHotKey != nil else {
                errorMessage = "This shortcut is unavailable. Choose a different one."
                return
            }
        }

        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = newHotKey
        choice = newChoice
        UserDefaults.standard.set(newChoice.rawValue, forKey: preferenceKey)
    }

    func stop() {
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
            guard status == noErr, id.signature == 0x504C5550, id.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async {
                WindowManager.shared.toggleShelfWindow()
            }
            return noErr
        }, 1, &event, nil, &handler)
        return status == noErr
    }
}
