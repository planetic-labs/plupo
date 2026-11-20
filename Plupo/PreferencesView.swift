//
//  PreferencesView.swift
//  Plupo
//
//  Created by Antigravity on 06.06.2026.
//

import SwiftUI
import ServiceManagement

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
                                Text("Alignment:")
                                    .frame(width: 110, alignment: .leading)
                                Picker("", selection: $prefs.alignment) {
                                    ForEach(ShelfAlignment.allCases, id: \.self) { align in
                                        Text(align.rawValue).tag(align)
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
                        ForEach(ShelfShortcutChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    if let error = shelfShortcut.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Picker("Add from Clipboard", selection: Binding(
                        get: { shelfShortcut.clipboardChoice },
                        set: { shelfShortcut.applyClipboard($0) }
                    )) {
                        ForEach(ClipboardShortcutChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
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
                    shortcutRow("Toggle shelf (Plupo menu)", keys: "⌘Y")
                    shortcutRow("Open Preferences", keys: "⌘,")
                    shortcutRow("Quit Plupo", keys: "⌘Q")
                    shortcutRow("Close Preferences", keys: "Return")
                }
                .padding(8)
            }

            GroupBox("Shelf gestures") {
                VStack(spacing: 8) {
                    shortcutRow("Select multiple cards", keys: "⌘-click")
                    shortcutRow("Move original files", keys: "⌘-drag from shelf")
                }
                .padding(8)
            }
        }
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
