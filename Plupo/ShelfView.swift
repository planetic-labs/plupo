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
    @State private var isSwiftUIDropTargeted = false
    private var isTargeted: Bool { isSwiftUIDropTargeted || viewModel.isNativeFileDropTargeted }
    @EnvironmentObject var prefs: PreferencesStore
    
    var body: some View {
        ZStack {
            // Vibancy Acrylic Background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                .cornerRadius(12)
            
            if viewModel.isPointerDropTarget {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Drop onto Plupo")
            } else {
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
                                        if let stack = viewModel.stacks.first(where: { $0.members.contains(item.id) }) {
                                            if stack.members.first == item.id {
                                                stackHeader(stack, first: item)
                                                    .id(stack.id)
                                            }
                                            if viewModel.expandedStacks.contains(stack.id) {
                                                ShelfItemView(item: item, viewModel: viewModel)
                                                    .padding(.leading, 8)
                                                    .id(item.id)
                                            }
                                        } else {
                                            ShelfItemView(item: item, viewModel: viewModel)
                                                .id(item.id)
                                        }
                                    }
                                }
                                .padding(8)
                                .onChange(of: viewModel.items.count) {
                                    // Auto scroll to latest item
                                    if let lastItem = viewModel.items.last {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            let stack = viewModel.stacks.first { $0.members.contains(lastItem.id) }
                                            let target = stack.flatMap {
                                                viewModel.expandedStacks.contains($0.id) ? nil : $0.id
                                            } ?? lastItem.id
                                            proxy.scrollTo(target, anchor: .bottom)
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
        }
        .contentShape(Rectangle())
        .edgesIgnoringSafeArea(.all)
        .overlay(
            // Highlight border when dragging files over Plupo
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargeted ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isTargeted ? 2 : 1)
                .allowsHitTesting(false)
        )
        // Set up drop destination
        .onDrop(of: [.item, .fileURL, .url, .plainText], isTargeted: $isSwiftUIDropTargeted) { providers in
            return viewModel.handleDroppedProviders(providers)
        }
    }
    
    private func stackHeader(_ stack: ShelfViewModel.Stack, first: ShelfItem) -> some View {
        let expanded = viewModel.expandedStacks.contains(stack.id)
        return HStack(spacing: 4) {
            Label("\(stack.members.count) files", systemImage: "square.stack")
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
                .overlay {
                    NativeDragSource(item: first, viewModel: viewModel, stack: stack) {
                        viewModel.toggleStack(stack.id)
                    }
                    .help("Drag the whole stack")
                }
            Button {
                viewModel.toggleStack(stack.id)
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse stack" : "Expand stack")
        }
        .padding(.horizontal, 8)
        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    // Header View
    private var headerView: some View {
        HStack {
            Text("Plupo")
                .fixedSize(horizontal: true, vertical: false)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { _ in WindowManager.shared.moveShelfWithPointer() }
                    .onEnded { _ in WindowManager.shared.finishMovingShelf() })
                .help("Drag to move the shelf")

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
