//
//  PreferencesStore.swift
//  Plupo
//
//  Created by Antigravity on 06.06.2026.
//

import Foundation
import Combine
import ServiceManagement

enum ShelfPosition: String, CaseIterable {
    case left = "Left"
    case right = "Right"
}

enum ShelfAlignment: String, CaseIterable {
    case top = "Top"
    case center = "Center"
    case bottom = "Bottom"
}

enum ShowBehavior: String, CaseIterable {
    case dragStarts = "When Drag Starts"
    case always = "Always Visible"
    case shortcut = "Shortcut Only"

    var title: String {
        self == .dragStarts ? "Automatic" : (self == .shortcut ? "Manual (Menu Bar)" : rawValue)
    }
}

enum ShakeSensitivity: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var minimumDistance: CGFloat {
        switch self {
        case .low: return 28
        case .medium: return 18
        case .high: return 10
        }
    }
}

enum IconSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
}

class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()
    
    private let defaults = UserDefaults.standard
    
    @Published var position: ShelfPosition {
        didSet { defaults.set(position.rawValue, forKey: "position") }
    }
    
    @Published var alignment: ShelfAlignment {
        didSet { defaults.set(alignment.rawValue, forKey: "alignment") }
    }
    
    @Published var showBehavior: ShowBehavior {
        didSet { defaults.set(showBehavior.rawValue, forKey: "showBehavior") }
    }
    
    @Published var showOnDragStart: Bool {
        didSet { defaults.set(showOnDragStart, forKey: "showOnDragStart") }
    }

    @Published var showOnShake: Bool {
        didSet { defaults.set(showOnShake, forKey: "showOnShake") }
    }

    @Published var shakeSensitivity: ShakeSensitivity {
        didSet { defaults.set(shakeSensitivity.rawValue, forKey: "shakeSensitivity") }
    }

    @Published var keepItemsAfterDrag: Bool {
        didSet { defaults.set(keepItemsAfterDrag, forKey: "keepItemsAfterDrag") }
    }
    
    @Published var iconSize: IconSize {
        didSet { defaults.set(iconSize.rawValue, forKey: "iconSize") }
    }
    
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginRequiresApproval = false
    @Published var loginError: String?

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginRequiresApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled && SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                try SMAppService.mainApp.register()
            } else if !enabled && SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = "Could not update launch at login. Install a signed copy of Plupo in Applications and try again."
        }
        refreshLoginStatus()
    }

    private init() {
        self.position = ShelfPosition(rawValue: defaults.string(forKey: "position") ?? "") ?? .right
        self.alignment = ShelfAlignment(rawValue: defaults.string(forKey: "alignment") ?? "") ?? .center
        self.showBehavior = ShowBehavior(rawValue: defaults.string(forKey: "showBehavior") ?? "") ?? .dragStarts
        self.showOnDragStart = defaults.object(forKey: "showOnDragStart") as? Bool ?? true
        self.shakeSensitivity = ShakeSensitivity(rawValue: defaults.string(forKey: "shakeSensitivity") ?? "") ?? .medium
        self.showOnShake = defaults.object(forKey: "showOnShake") as? Bool ?? false
        self.keepItemsAfterDrag = defaults.object(forKey: "keepItemsAfterDrag") as? Bool ?? false
        self.iconSize = IconSize(rawValue: defaults.string(forKey: "iconSize") ?? "") ?? .medium
        defaults.removeObject(forKey: "launchAtLogin")
        refreshLoginStatus()
    }
}
