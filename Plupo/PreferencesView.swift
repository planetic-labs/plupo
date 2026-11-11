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
    @ObservedObject private var screenshots = ScreenshotMonitor.shared
    @ObservedObject private var updates = UpdateChecker.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Settings Banner
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plupo")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Power up your drag-and-drop workflow.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .background(Color.primary.opacity(0.03))
            
            Divider()
            
            // Preferences Form
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Section 1: Window Position & Behavior
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
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                    
                    // Section 2: Items & Dragging
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

                    GroupBox(label: Text("Updates").font(.system(size: 11, weight: .bold))) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Automatically check for updates", isOn: $updates.automaticallyChecks)
                            Text("Checks GitHub once a day. Updates are downloaded and installed manually.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button(updates.isChecking ? "Checking…" : "Check for Updates…") {
                                updates.check()
                            }
                            .disabled(updates.isChecking)
                        }
                        .padding(8)
                    }

                    // Section 3: General System
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
                }
                .padding(20)
            }
            
            Divider()
            
            // Bottom bar
            HStack {
                Spacer()
                Button("Done") {
                    // Close the window using the WindowManager or standard NSApp closing
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 450, height: 460)
        .onAppear { prefs.refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            prefs.refreshLoginStatus()
        }
    }
}

#Preview {
    PreferencesView()
        .environmentObject(PreferencesStore.shared)
}
