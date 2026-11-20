//
//  ShelfItemView.swift
//  Plupo
//
//  Created by Antigravity on 06.06.2026.
//

import SwiftUI
import AppKit

struct ShelfItemView: View {
    let item: ShelfItem
    @ObservedObject var viewModel: ShelfViewModel
    
    @State private var isHovering = false
    @EnvironmentObject var prefs: PreferencesStore
    
    var body: some View {
        HStack(spacing: 8) {
            // Icon / Thumbnail representation
            thumbnailView
                .frame(width: thumbnailSize, height: thumbnailSize)
                .cornerRadius(6)
                .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
            
            // Text details
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(item.subtitle)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Action Buttons (visible on hover)
            if isHovering {
                actionButtons
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(6)
        .frame(height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(viewModel.selectedIDs.contains(item.id) ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            NativeDragSource(item: item, viewModel: viewModel, preview: showQuickLook)
                .help("Command-click to select multiple items. While dragging originals, hold Command to move or Option to copy.")
                // Keep native dragging away from the hover action buttons.
                .padding(.trailing, isHovering ? 66 : 0)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }

    }
    
    // Custom Thumbnail View
    @ViewBuilder
    private var thumbnailView: some View {
        Image(nsImage: item.thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(4)
            .background(Color.primary.opacity(0.04))
    }
    
    // Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 4) {
            // Quick Look Button
            Button(action: { showQuickLook() }) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Quick Look")
            
            // Lock Button
            Button(action: { viewModel.toggleLock(for: item) }) {
                Image(systemName: item.isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(item.isLocked ? .accentColor : .secondary)
                    .frame(width: 18, height: 18)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(item.isLocked ? "Unlock item" : "Lock item to keep it on shelf")
            
            // Remove Button
            Button(action: { viewModel.removeItem(item) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: 18, height: 18)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Remove item")
        }
    }
    
    // Quick Look implementation
    private func showQuickLook() {
        PreviewController.shared.show(item)
    }

    // Size settings based on Preferences
    private var cardHeight: CGFloat {
        switch prefs.iconSize {
        case .small: return 42
        case .medium: return 52
        case .large: return 64
        }
    }
    
    private var thumbnailSize: CGFloat {
        switch prefs.iconSize {
        case .small: return 30
        case .medium: return 40
        case .large: return 50
        }
    }
}
