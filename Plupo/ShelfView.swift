//
//  ShelfView.swift
//  Plupo
//
//  Created by Antigravity on 06.06.2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var viewModel: ShelfViewModel
    @State private var isTargeted = false
    @EnvironmentObject var prefs: PreferencesStore
    
    var body: some View {
        ZStack {
            // Vibancy Acrylic Background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                .cornerRadius(12)
            
            VStack(spacing: 0) {
                // Header (App Name / Controls)
                headerView
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                
                Divider()
                    .background(Color.primary.opacity(0.1))
                
                // Content area
                if viewModel.items.isEmpty {
                    placeholderView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        ScrollViewReader { proxy in
                            LazyVStack(spacing: 8) {
                                ForEach(viewModel.items) { item in
                                    ShelfItemView(item: item, viewModel: viewModel)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: prefs.position == .left ? .leading : .trailing).combined(with: .opacity),
                                            removal: .scale(scale: 0.9).combined(with: .opacity)
                                        ))
                                        .id(item.id)
                                }
                            }
                            .padding(8)
                            .onChange(of: viewModel.items.count) {
                                // Auto scroll to latest item
                                if let lastItem = viewModel.items.last {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        proxy.scrollTo(lastItem.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Divider()
                    .background(Color.primary.opacity(0.1))
                
                if let error = viewModel.dropError {
                    HStack(alignment: .top) {
                        Text(error).font(.caption2).foregroundStyle(.secondary)
                        Button { viewModel.dismissDropError() } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss message")
                    }
                    .padding(8)
                }

                // Footer (Action Controls)
                footerView
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
        .edgesIgnoringSafeArea(.all)
        .overlay(
            // Highlight border when dragging files over Plupo
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargeted ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isTargeted ? 2 : 1)
        )
        // Set up drop destination
        .onDrop(of: [.item, .fileURL, .url, .plainText], isTargeted: $isTargeted) { providers in
            return viewModel.handleDroppedProviders(providers)
        }
    }
    
    // Header View
    private var headerView: some View {
        HStack {
            Text("Plupo")
                .fixedSize(horizontal: true, vertical: false)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(0.8))
            
            Spacer()
            
            // Clear All Button
            if !viewModel.items.isEmpty {
                Button(action: {
                    withAnimation(.spring()) {
                        viewModel.clearAll()
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear all unlocked items")
            }
        }
    }
    
    // Footer View
    private var footerView: some View {
        HStack {
            // Preferences Button
            Button(action: {
                WindowManager.shared.showPreferencesWindow()
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open settings")
            
            Spacer()
            
            // Item Counter
            if !viewModel.usesCompactLayout {
                Text("\(viewModel.items.count) items")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            // Hide Panel Button
            Button(action: {
                WindowManager.shared.hideShelfWindow()
            }) {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(prefs.position == .left ? 180 : 0))
            }
            .buttonStyle(.plain)
            .help("Minimize Plupo Shelf")
        }
    }
    
    // Empty State Placeholder
    private var placeholderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.6))
            
            if !viewModel.usesCompactLayout {
                Text("Drag items here")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .help("Drag items here")
        .accessibilityLabel("Drag items here")
        .opacity(isTargeted ? 0.4 : 1.0)
    }
}
