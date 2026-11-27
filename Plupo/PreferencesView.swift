//
//  PreferencesView.swift
//  Plupo
//
//  Created by Antigravity on 06.06.2026.
//

import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct PreferencesView: View {
    @EnvironmentObject var prefs: PreferencesStore
    @ObservedObject private var shelfShortcut = ShelfShortcut.shared
    @ObservedObject private var downloads = ScreenshotMonitor.downloads
    @ObservedObject private var screenshots = ScreenshotMonitor.shared
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                preferencesPage {
                    GroupBox(label: Text("Position & Behavior").font(.system(size: 11, weight: .bold))) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Screen Edge:")
                                    .frame(width: 110, alignment: .leading)
                                Picker("", selection: $prefs.position) {
                                    ForEach(ShelfPosition.allCases, id: \.self) { pos in
                                        Text(pos.rawValue).tag(pos)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            HStack {
                                Text("Show Shelf:")
                                    .frame(width: 110, alignment: .leading)
                                Picker("", selection: $prefs.showBehavior) {
                                    ForEach(ShowBehavior.allCases, id: \.self) { behavior in
                                        Text(behavior.title).tag(behavior)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            Toggle("Show when a drag starts", isOn: $prefs.showOnDragStart)
                                .disabled(prefs.showBehavior != .dragStarts)
                            Toggle("Show near screen edge", isOn: $prefs.showNearScreenEdge)
                                .disabled(prefs.showBehavior != .dragStarts)
                            Toggle("Show when shaking while dragging", isOn: $prefs.showOnShake)
                                .disabled(prefs.showBehavior != .dragStarts)
                            Picker("Shake sensitivity", selection: $prefs.shakeSensitivity) {
                                ForEach(ShakeSensitivity.allCases, id: \.self) { level in
                                    Text(level.rawValue).tag(level)
                                }
                            }
                            .disabled(prefs.showBehavior != .dragStarts || !prefs.showOnShake)
                            Toggle("Drop files near the camera notch", isOn: $prefs.dropToNotch)
                            Text("On MacBooks with a notch, drag files to the strip just below the camera.")
                                .font(.caption).foregroundStyle(.secondary)

                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                    GroupBox("Excluded Apps") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Skip automatic shelf activation when a drag starts in these apps.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(prefs.excludedDragApps.keys.sorted(), id: \.self) { id in
                                HStack {
                                    Text(prefs.excludedDragApps[id] ?? id)
                                    Spacer()
                                    Button {
                                        prefs.excludedDragApps.removeValue(forKey: id)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .accessibilityLabel("Remove \(prefs.excludedDragApps[id] ?? id)")
                                }
                            }
                            Button("Add App…", action: addExcludedDragApp)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    GroupBox(label: Text("Items & Dragging").font(.system(size: 11, weight: .bold))) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Card Size:")
                                    .frame(width: 110, alignment: .leading)
                                Picker("", selection: $prefs.iconSize) {
                                    ForEach(IconSize.allCases, id: \.self) { size in
                                        Text(size.rawValue).tag(size)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            Toggle("Keep items on shelf after dragging them out", isOn: $prefs.keepItemsAfterDrag)
                                .font(.system(size: 11))

                            Text("By default, items are automatically removed from Plupo when you drag them into another application.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.leading, 18)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                }
                .tabItem { Label("Shelf", systemImage: "rectangle.righthalf.inset.filled") }

                preferencesPage {
                    GroupBox(label: Text("Screenshots").font(.system(size: 11, weight: .bold))) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Add new screenshots to the shelf", isOn: Binding(
                                get: { screenshots.isMonitoring },
                                set: { screenshots.setEnabled($0) }
                            ))
                            .disabled(screenshots.folder == nil)

                            HStack {
                                Button(screenshots.folder == nil ? "Choose Folder…" : "Change Folder…") {
                                    screenshots.chooseFolder()
                                }
                                if let folder = screenshots.folder {
                                    Text(folder.lastPathComponent)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(folder.path)
                                }
                            }

                            if let error = screenshots.errorMessage {
                                Text(error).font(.caption).foregroundStyle(.red)
                            } else if screenshots.isMonitoring {
                                Text(screenshots.detectedScreenshot
                                     ? "Screenshot added to the shelf."
                                     : "Take a screenshot with Shift-Command-4 to test this folder.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Choose the folder where macOS saves screenshots.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }
                    GroupBox(label: Text("Folder Monitoring").font(.system(size: 11, weight: .bold))) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Add new files to the shelf", isOn: Binding(
                                get: { downloads.isMonitoring },
                                set: { downloads.setEnabled($0) }
                            ))
                            .disabled(downloads.folder == nil)

                            HStack {
                                Button(downloads.folder == nil ? "Choose Folder…" : "Change Folder…") {
                                    downloads.chooseFolder()
                                }
                                if let folder = downloads.folder {
                                    Text(folder.lastPathComponent).lineLimit(1).help(folder.path)
                                }
                            }
                            if let error = downloads.errorMessage {
                                Text(error).font(.caption).foregroundStyle(.red)
                            } else {
                                Text("Choose Downloads or another folder. Only newly added files appear on the shelf.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }
                }
                .tabItem { Label("Monitoring", systemImage: "folder") }

                preferencesPage {
                    shortcutSettings
                }
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

                preferencesPage {
                    GroupBox(label: Text("System").font(.system(size: 11, weight: .bold))) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Launch Plupo at login", isOn: Binding(get: { prefs.launchAtLogin }, set: { prefs.setLaunchAtLogin($0) }))
                                .font(.system(size: 11))

                            if prefs.loginRequiresApproval {
                                Button("Allow in System Settings…") {
                                    SMAppService.openSystemSettingsLoginItems()
                                }
                            }
                            if let error = prefs.loginError {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }

                            Text("Starts the app automatically when you log into your Mac so it's always ready.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.leading, 18)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                    GroupBox(label: Text("Updates").font(.system(size: 11, weight: .bold))) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Check for updates on launch", isOn: $updates.automaticallyChecks)
                            Text("Checks GitHub when Plupo starts. Updates are downloaded and installed manually.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button(updates.isChecking ? "Checking…" : "Check for Updates…") {
                                updates.check()
                            }
                            .disabled(updates.isChecking)
                        }
                        .padding(8)
                    }
                }
                .tabItem { Label("General", systemImage: "gearshape") }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Divider()

            HStack {
                Spacer()
                Button("Done") { NSApp.keyWindow?.close() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 500, height: 420)
        .onAppear { prefs.refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            prefs.refreshLoginStatus()
        }
    }

    private func preferencesPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    private var shortcutSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Global") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show shelf while holding Fn", isOn: $shelfShortcut.showShelfWhileHoldingFn)

                    Picker("Toggle Shelf Shortcut", selection: Binding(
                        get: { shelfShortcut.choice },
                        set: { shelfShortcut.apply($0) }
                    )) {
                        ForEach(ShelfShortcutChoice.allCases.filter { $0 != .custom || shelfShortcut.customShelf != nil }) { choice in
                            Text(choice == .custom ? shelfShortcut.customShelf?.title ?? choice.rawValue : choice.rawValue).tag(choice)
                        }
                    }
                    Button("Record Shelf Shortcut…") { shelfShortcut.recordCustom(clipboard: false) }
                    if let error = shelfShortcut.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Picker("Add from Clipboard", selection: Binding(
                        get: { shelfShortcut.clipboardChoice },
                        set: { shelfShortcut.applyClipboard($0) }
                    )) {
                        ForEach(ClipboardShortcutChoice.allCases.filter { $0 != .custom || shelfShortcut.customClipboard != nil }) { choice in
                            Text(choice == .custom ? shelfShortcut.customClipboard?.title ?? choice.title : choice.title).tag(choice)
                        }
                    }
                    Button("Record Clipboard Shortcut…") { shelfShortcut.recordCustom(clipboard: true) }
                    if let error = shelfShortcut.clipboardError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    if shelfShortcut.choice == .yoink || shelfShortcut.clipboardChoice == .doubleF5 {
                        Text("If F5 controls a system feature, press Fn–F5.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox("Menu and Preferences") {
                VStack(spacing: 8) {
                    ForEach(MenuShortcutAction.allCases) { action in
                        let disabled = shelfShortcut.disabledMenuShortcuts.contains(action.rawValue)
                        HStack {
                            shortcutRow(action.rawValue, keys: disabled ? "Off" :
                                (shelfShortcut.menuShortcuts[action.rawValue]?.title ?? "⌘" + action.defaultKey.uppercased()))
                            Menu("Change") {
                                Button("Record…") { shelfShortcut.recordMenuShortcut(action) }
                                Button("Off") { shelfShortcut.disabledMenuShortcuts.insert(action.rawValue) }
                                Button("Use Default") {
                                    shelfShortcut.menuShortcuts.removeValue(forKey: action.rawValue)
                                    shelfShortcut.disabledMenuShortcuts.remove(action.rawValue)
                                }
                            }
                            .fixedSize()
                        }
                    }
                    shortcutRow("Close Preferences", keys: "Return")
                }
                .padding(8)
            }

            GroupBox("Shelf gestures") {
                VStack(spacing: 8) {
                    shortcutRow("Select multiple cards", keys: "⌘-click")
                    shortcutRow("Move original files", keys: "⌘ during drag")
                    shortcutRow("Copy files", keys: "⌥ during drag")
                }
                .padding(8)
            }
        }
    }

    private func addExcludedDragApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        prefs.excludedDragApps[id] = url.deletingPathExtension().lastPathComponent
    }

    private func shortcutRow(_ action: String, keys: String) -> some View {
        LabeledContent(action) {
            Text(keys).monospaced()
        }
    }
}

#Preview {
    PreferencesView()
        .environmentObject(PreferencesStore.shared)
}
