//
//  YippyViewModel.swift
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
import Observation

struct Results {
    let items: [HistoryItem]
    let isSearchResult: Bool
}

@Observable
class YippyViewModel {
    
    var searchBarValue: String = ""
    var itemCountLabel: String = ""
    var isSearchBarFocused: Bool = false
    var isVimMode: Bool = false
    
    // Vim mode timing tracking
    private var jKeyPressTime: Date?
    private var lastTypingTime: Date?
    private let vimModeActivationDelay: TimeInterval = 0.1 // 100ms
    private let typingCooldownTime: TimeInterval = 0.5 // 500ms cooldown after typing
    private var pendingJTimer: Timer?
    private var shouldInsertPendingJ = false
    
    var yippyHistory = YippyHistory(history: State.main.history, items: [])
    
    private var searchEngine = SearchEngine(data: [])
    private let disposeBag = DisposeBag()
    
    var isPreviewShowing = false
    
    var panelPosition: Axis.Set = .vertical
    
    var itemGroups = BehaviorRelay<[String]>(value: ["Clipboard", "Favourites", "Clipboard", "Favourites", "Clipboard", "Favourites"])
    
    var isRichText = Settings.main.showsRichText

    private(set) var selectedItem: HistoryItem?
    
    deinit {
        cancelDelayedJInsertion()
    }
    
    private let results = BehaviorRelay(value: Results(items: [], isSearchResult: false))
    private let selected = BehaviorRelay<Int?>(value: nil)
    
    func onAppear() {
        State.main.history.subscribe(onNext: onHistoryChange)
        
        State.main.panelPosition.subscribe(onNext: onWindowPanelPositionChanged).disposed(by: disposeBag)
        
        State.main.showsRichText.distinctUntilChanged().subscribe(onNext: onShowsRichText).disposed(by: disposeBag)
        
        Observable.combineLatest(
            results,
            selected.distinctUntilChanged().withPrevious(startWith: nil)
        )
        .observe(on: MainScheduler.asyncInstance)
        .subscribe(onNext: onAllChange)
        .disposed(by: disposeBag)
        
        // TODO: Fix hack to make onAllChange run initially
        selected.accept(1)
        resetSelected()
        
        YippyHotKeys.downArrow.onDown(goToNextItem)
        YippyHotKeys.downArrow.onLong(goToNextItem)
        YippyHotKeys.pageDown.onDown(goToNextItem)
        YippyHotKeys.pageDown.onLong(goToNextItem)
        YippyHotKeys.upArrow.onDown(goToPreviousItem)
        YippyHotKeys.upArrow.onLong(goToPreviousItem)
        YippyHotKeys.pageUp.onDown(goToPreviousItem)
        YippyHotKeys.pageUp.onLong(goToPreviousItem)
        YippyHotKeys.escape.onDown(close)
        YippyHotKeys.return.onDown(pasteSelected)
        YippyHotKeys.ctrlAltCmdLeftArrow.onDown { State.main.panelPosition.accept(.left) }
        YippyHotKeys.ctrlAltCmdRightArrow.onDown { State.main.panelPosition.accept(.right) }
        YippyHotKeys.ctrlAltCmdDownArrow.onDown { State.main.panelPosition.accept(.bottom) }
        YippyHotKeys.ctrlAltCmdUpArrow.onDown { State.main.panelPosition.accept(.top) }
        YippyHotKeys.ctrlDelete.onDown(deleteSelected)
        YippyHotKeys.space.onDown(togglePreview)
        YippyHotKeys.cmdBackslash.onDown(focusSearchBar)
        
        // Paste hot keys
        YippyHotKeys.cmd0.onDown { self.shortcutPressed(key: 0) }
        YippyHotKeys.cmd1.onDown { self.shortcutPressed(key: 1) }
        YippyHotKeys.cmd2.onDown { self.shortcutPressed(key: 2) }
        YippyHotKeys.cmd3.onDown { self.shortcutPressed(key: 3) }
        YippyHotKeys.cmd4.onDown { self.shortcutPressed(key: 4) }
        YippyHotKeys.cmd5.onDown { self.shortcutPressed(key: 5) }
        YippyHotKeys.cmd6.onDown { self.shortcutPressed(key: 6) }
        YippyHotKeys.cmd7.onDown { self.shortcutPressed(key: 7) }
        YippyHotKeys.cmd8.onDown { self.shortcutPressed(key: 8) }
        YippyHotKeys.cmd9.onDown { self.shortcutPressed(key: 9) }
        
        bindHotKeyToYippyWindow(YippyHotKeys.downArrow, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.upArrow, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.return, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.escape, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.pageDown, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.pageUp, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.ctrlAltCmdLeftArrow, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.ctrlAltCmdRightArrow, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.ctrlAltCmdDownArrow, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.ctrlAltCmdUpArrow, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd0, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd1, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd2, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd3, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd4, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd5, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd6, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd7, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd8, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd9, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.ctrlDelete, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.space, disposeBag: disposeBag)
    }
    
    func resetSelected() {
        if yippyHistory.items.count > 0 {
            selected.accept(0)
        }
        else {
            selected.accept(nil)
        }
    }
    
    func onHistoryChange(_ history: [HistoryItem], change: History.Change) {
        updateSearchEngine(items: history)
        if !searchBarValue.isEmpty {
            runSearch()
        }
        else {
            results.accept(Results(items: history, isSearchResult: false))
            switch change {
            case .insert(let i):
                if i == 0 {
                    incrementSelected()
                }
                break;
            default: break;
            }
        }
    }
    
    func onWindowPanelPositionChanged(_ position: PanelPosition) {
        switch position {
        case .right, .left:
            panelPosition = .vertical
        case .top, .bottom:
            panelPosition = .horizontal
        default:
            panelPosition = .vertical
        }
    }
    
    func updateSearchEngine(items: [HistoryItem]) {
        self.searchEngine = SearchEngine(data: items.compactMap({$0.getPlainString()}))
    }
    
    func onAllChange(_ results: Results, _ selected: (Int?, Int?)) {
        if results.items != self.yippyHistory.items {
            if results.isSearchResult {
                self.itemCountLabel = "\(results.items.count) matches"
            }
            else {
                self.itemCountLabel = "\(results.items.count) items"
            }
            
            self.yippyHistory = YippyHistory(history: State.main.history, items: results.items)
        }
        
        if let selectedIndex = selected.1, yippyHistory.items.indices.contains(selectedIndex) {
            self.selectedItem = yippyHistory.items[selectedIndex]
            
            if self.isPreviewShowing {
                State.main.previewHistoryItem.accept(self.yippyHistory.items[selectedIndex])
            }
        }
    }
    
    func onShowsRichText(_ showsRichText: Bool) {
        isRichText = showsRichText
    }
    
    func bindHotKeyToYippyWindow(_ hotKey: YippyHotKey, disposeBag: DisposeBag) {
        State.main.isHistoryPanelShown
            .distinctUntilChanged()
            .subscribe(onNext: { [] in
                hotKey.isPaused = !$0
            })
            .disposed(by: disposeBag)
    }
    
    func goToNextItem() {
        incrementSelected()
    }
    
    func goToPreviousItem() {
        decrementSelected()
    }
    
    func pasteSelected() {
        if let selected = self.selected.value {
            paste(selected: selected)
        }
    }
    
    func deleteSelected() {
        if let selected = self.selected.value {
            self.selected.accept(yippyHistory.delete(selected: selected))
        }
    }
    
    func paste(at index: Int) {
        paste(selected: index)
    }
    
    func delete(at index: Int) {
        self.selected.accept(yippyHistory.delete(selected: index))
    }
    
    func onSelectItem(at index: Int) {
        self.selected.accept(index)
    }
    
    func close() {
        isPreviewShowing = false
        State.main.isHistoryPanelShown.accept(false)
        State.main.previewHistoryItem.accept(nil)
        resetSelected()
    }
    
    func shortcutPressed(key: Int) {
        paste(selected: key)
    }
    
    func togglePreview() {
        if let selected = self.selected.value {
            isPreviewShowing = !isPreviewShowing
            if isPreviewShowing {
                State.main.previewHistoryItem.accept(yippyHistory.items[selected])
            }
            else {
                State.main.previewHistoryItem.accept(nil)
            }
        }
    }
    
    func focusSearchBar() {
        NSApp.activate(ignoringOtherApps: true)
        self.isSearchBarFocused = true
    }
    
    // MARK: - Vim Mode Functions
    
    func onSearchFieldTyping() {
        lastTypingTime = Date()
        // Exit vim mode when user starts typing in search field
        if isVimMode && isSearchBarFocused {
            isVimMode = false
        }
    }
    
    func handleKeyPress(_ key: String) -> Bool {
        let now = Date()
        
        // Handle pending j insertion first
        if shouldInsertPendingJ {
            shouldInsertPendingJ = false
            pendingJTimer?.invalidate()
            pendingJTimer = nil
        }
        
        // Special handling for vim mode activation (jk sequence)
        if key == "j" && !isVimMode {
            // Check if we're in a typing cooldown period for j key
            if let lastTyping = lastTypingTime, now.timeIntervalSince(lastTyping) < typingCooldownTime {
                print("🔧 'j' key ignored - in typing cooldown")
                return false
            }
            
            jKeyPressTime = now
            print("🔧 'j' pressed - waiting for 'k' within \(vimModeActivationDelay * 1000)ms")
            
            // If search bar is focused, delay the insertion of 'j' to see if 'k' follows
            if isSearchBarFocused {
                scheduleDelayedJInsertion()
                return true // Consume the event temporarily
            } else {
                // Not in search bar, just consume to prevent any action
                return true
            }
        }
        
        if key == "k" && !isVimMode {
            if let jTime = jKeyPressTime, now.timeIntervalSince(jTime) <= vimModeActivationDelay {
                // jk pressed within the time window - enter vim mode
                print("🔧 'jk' sequence detected - entering vim mode")
                cancelDelayedJInsertion() // Cancel the pending j insertion
                enterVimMode()
                jKeyPressTime = nil
                return true // Always consume this k to prevent it from going to search
            }
            jKeyPressTime = nil
        }
        
        // Handle vim mode keys
        if isVimMode {
            switch key {
            case "j":
                print("🔧 'j' pressed in vim mode - moving down")
                goToNextItem()
                return true
                
            case "k":
                print("🔧 'k' pressed in vim mode - moving up") 
                goToPreviousItem()
                return true
                
            case "i":
                print("🔧 'i' pressed in vim mode - exiting to insert mode")
                exitVimMode()
                return true
                
            default:
                // In vim mode, don't let other keys through to search field
                return true
            }
        }
        
        // Not in vim mode and not a vim activation sequence
        if isSearchBarFocused {
            print("🔧 Key '\(key)' passed through to search bar")
            return false
        }
        
        // Reset j key timing for other keys when not in search
        if jKeyPressTime != nil && key != "j" && key != "k" {
            print("🔧 '\(key)' pressed - resetting 'j' timing")
            jKeyPressTime = nil
            cancelDelayedJInsertion()
        }
        
        return false
    }
    
    func enterVimMode() {
        guard !isVimMode else { 
            print("🔧 Already in vim mode")
            return 
        }
        print("🔧 Entering vim mode")
        isVimMode = true
        // Unfocus search bar when entering vim mode
        if isSearchBarFocused {
            isSearchBarFocused = false
            print("🔧 Unfocused search bar when entering vim mode")
        }
    }
    
    func exitVimMode() {
        guard isVimMode else { 
            print("🔧 Not in vim mode, cannot exit")
            return 
        }
        print("🔧 Exiting vim mode")
        isVimMode = false
        // Focus search bar when exiting vim mode with 'i'
        focusSearchBar()
    }
    
    // MARK: - Delayed J Insertion
    
    private func scheduleDelayedJInsertion() {
        cancelDelayedJInsertion() // Cancel any existing timer
        shouldInsertPendingJ = true
        
        pendingJTimer = Timer.scheduledTimer(withTimeInterval: vimModeActivationDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.shouldInsertPendingJ {
                print("🔧 Delayed insertion of 'j' - no 'k' detected within timeout")
                DispatchQueue.main.async {
                    self.insertJIntoSearchField()
                }
                self.shouldInsertPendingJ = false
                self.jKeyPressTime = nil
            }
        }
    }
    
    private func cancelDelayedJInsertion() {
        pendingJTimer?.invalidate()
        pendingJTimer = nil
        shouldInsertPendingJ = false
    }
    
    private func insertJIntoSearchField() {
        guard isSearchBarFocused else { return }
        print("🔧 Inserting delayed 'j' into search field")
        searchBarValue += "j"
        runSearch()
    }
    
    func runSearch() {
        searchEngine.search(query: self.searchBarValue, completion: { result in
            if (result.query.query.isEmpty) {
                self.results.accept(Results(items: State.main.history.items, isSearchResult: false))
                return
            }
            
            var filteredData = [HistoryItem]()
            for i in result.results {
                filteredData.append(State.main.history.items[i])
            }
            
            self.results.accept(Results(items: filteredData, isSearchResult: true))
        })
    }
    
    private func incrementSelected() {
        guard let s = selected.value else {
            if yippyHistory.items.count > 0 {
                selected.accept(0)
            }
            return
        }
        if s < yippyHistory.items.count - 1 {
            selected.accept(s + 1)
        }
    }
    
    private func decrementSelected() {
        guard let s = selected.value else {
            if yippyHistory.items.count > 0 {
                selected.accept(0)
            }
            return
        }
        if s > 0 {
            selected.accept(s - 1)
        }
    }
    
    private func paste(selected: Int) {
        self.close()
        yippyHistory.paste(selected: selected)
    }
}
