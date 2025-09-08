//
//  YippyView.swift
//  Yippy
//
//  Created by v.prusakov on 2/13/24.
//  Copyright © 2024 MatthewDavidson. All rights reserved.
//

import Cocoa
import HotKey
import RxSwift
import RxRelay
import RxCocoa
import SwiftUI

class SUIYippyViewController: NSHostingController<YippyView> {
    required init?(coder: NSCoder) {
        super.init(coder: coder, rootView: YippyView())
    }
}

struct YippyView: View {
    
    enum Focus {
        case searchbar
        case hidden // Dummy focus state to prevent auto-focus
    }
    
    @Bindable var viewModel = YippyViewModel()
    @FocusState private var focusState: Focus?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 4) {
                // Hidden focusable element to prevent search field auto-focus
                TextField("", text: .constant(""))
                    .focused($focusState, equals: .hidden)
                    .opacity(0)
                    .frame(height: 0)
                    .allowsHitTesting(false)
                ZStack {
                    Text("Yippy")
                        .font(.title)
                    
                    HStack {
                        // Vim mode indicator
                        if viewModel.isVimMode {
                            HStack(spacing: 4) {
                                Text("VIM")
                                    .font(.caption.weight(.bold))
                                Text("j/k=nav, i=edit")
                                    .font(.caption2)
                                    .opacity(0.8)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        
                        Spacer()
                        
                        Text(viewModel.itemCountLabel)
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
                
                TextField(text: $viewModel.searchBarValue, prompt: Text(viewModel.isVimMode ? "Press 'i' to search" : "Search or press 'jk' for vim mode")) {
                    Image(systemName: "magnifyingglass")
                }
                .focused($focusState, equals: .searchbar)
                .disabled(viewModel.isVimMode) // Disable editing in vim mode
                .opacity(viewModel.isVimMode ? 0.6 : 1.0) // Visual feedback when disabled
                .onTapGesture {
                    // Only focus when user explicitly clicks on search field
                    print("🔧 Search field clicked - focusing")
                    if viewModel.isVimMode {
                        // If in vim mode, clicking search field should exit vim mode
                        viewModel.exitVimMode()
                    } else {
                        focusState = .searchbar
                    }
                }
                .onAppear {
                    // Ensure search field starts unfocused
                    print("🔧 Search field appeared - starting unfocused")
                    DispatchQueue.main.async {
                        focusState = .hidden // Focus hidden element instead
                    }
                }
                .autocorrectionDisabled()
                .border(.secondary)
                .onChange(of: viewModel.searchBarValue) { _, _ in
                    viewModel.onSearchFieldTyping() // Track typing for vim mode cooldown
                    viewModel.runSearch()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                
                YippyHistoryTableView(viewModel: viewModel)
                    .onAppear {
                        viewModel.onAppear()
                        // Start with hidden element focused to prevent search auto-focus
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if focusState != .searchbar {
                                focusState = .hidden
                                print("🔧 Set initial focus to hidden element")
                            }
                        }
                    }
            }
        }
        .safeAreaPadding(.top, 48)
        .padding(.all, 4) // Add padding to respect window rounded corners
        .materialBlur(style: .sidebar)
        .onTapGesture {
            // Clicking outside search field unfocuses it and enables vim mode
            if focusState == .searchbar {
                focusState = .hidden
                print("🔧 Unfocused search field - vim keys now available")
                // Allow some time for the focus change to take effect
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    viewModel.isSearchBarFocused = false
                }
            }
        }
        .onKeyPress(.escape) {
            // Escape key unfocuses search field
            if focusState == .searchbar {
                focusState = .hidden
                print("🔧 Escape pressed - unfocused search field")
                // Update view model state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    viewModel.isSearchBarFocused = false
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress { keyPress in
            // Handle vim motion keys
            let key = keyPress.characters
            print("🔧 Key pressed: '\(key)' - isVimMode: \(viewModel.isVimMode), isFocused: \(focusState == .searchbar)")
            
            // Handle vim keys
            if viewModel.handleKeyPress(key) {
                return .handled
            }
            
            return .ignored
        }
        .onChange(of: viewModel.isSearchBarFocused) { _, newValue in
            print("🔧 ViewModel focus changed to: \(newValue)")
            if newValue == true {
                self.focusState = .searchbar
                // Exit vim mode when search field is focused
                if viewModel.isVimMode {
                    viewModel.isVimMode = false
                }
            } else {
                self.focusState = nil
            }
        }
        .onChange(of: focusState) { _, newValue in
            // Update the view model when focus changes
            let isFocused = (newValue == .searchbar)
            print("🔧 FocusState changed to: \(String(describing: newValue)) -> isFocused: \(isFocused)")
            viewModel.isSearchBarFocused = isFocused
        }
    }
}

struct YippyHistoryTableView: View {
    
    @Bindable var viewModel: YippyViewModel
    
    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView(viewModel.panelPosition) {
                    if viewModel.panelPosition == .horizontal {
                        LazyHStack(spacing: 12) {
                            content(proxy: proxy)
                        }
                    } else {
                        LazyVStack(spacing: 4) {
                            content(proxy: proxy)
                                .padding(.top, 8)
                        }
                    }
                }
                .onChange(of: viewModel.selectedItem) { oldValue, newValue in
                    if let value = newValue {
                        reader.scrollTo(value)
                    }
                }
            }
        }
        .environment(\.historyCellSettings, HistoryCellSettings())
    }
    
    func content(proxy: GeometryProxy) -> some View {
        ForEach(Array(viewModel.yippyHistory.items.enumerated()), id: \.element) { (index, item) in
            HistoryCellView(item: item, proxy: proxy, usingItemRtf: viewModel.isRichText)
                .clipShape(
                    RoundedRectangle(cornerRadius: 7)
                )
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(NSColor.windowBackgroundColor))
                )
                .overlay {
                    ZStack(alignment: .topLeading) {
                        if index < 10 {
                            VStack {
                                HStack {
                                    Spacer()
                                    
                                    Text("􀆔 + \(index)")
                                        .font(.system(size: 10))
                                        .padding(.all, 4)
                                        .foregroundStyle(Color.white)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.accentColor)
                                        )
                                }
                                
                                Spacer()
                            }
                        }
                        
                        if viewModel.selectedItem == item {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.accentColor, lineWidth: 6)
                        }
                    }
                }
                .onTapGesture {
                    viewModel.onSelectItem(at: index)
                }
                .contextMenu(
                    ContextMenu(menuItems: {
                        Button("Copy") {
                            viewModel.paste(at: index)
                        }
                        
                        Button("Delete") {
                            viewModel.delete(at: index)
                        }
                    })
                )
                .id(item)
                .draggable(item)
        }
    }
}
