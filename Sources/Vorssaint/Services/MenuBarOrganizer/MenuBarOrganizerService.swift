// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class MenuBarOrganizerService: ObservableObject {
    static let shared = MenuBarOrganizerService()

    @Published private(set) var items: [ManagedMenuBarItem] = []
    @Published private(set) var capabilities = MenuBarOrganizerCapabilities(
        canEnumerate: true,
        canMove: AXIsProcessTrusted(),
        canCapture: CGPreflightScreenCaptureAccess(),
        hasPrivateFrameAPI: DynamicMenuBarAPI.shared.hasWindowFrame)
    @Published private(set) var isRunning = false
    @Published private(set) var hiddenSectionShown = true
    @Published private(set) var alwaysHiddenSectionShown = true
    @Published private(set) var operationMessage: String?
    @Published private(set) var canUndo = false
    @Published private(set) var hotkeyRegistrationFailed = false

    private let provider = MenuBarWindowProvider()
    private let mover = MenuBarItemMover()
    private let hotkeys = MenuBarOrganizerHotkeyController()
    private var controlItem: MenuBarDividerItem?
    private var hiddenDivider: MenuBarDividerItem?
    private var alwaysHiddenDivider: MenuBarDividerItem?
    private var searchPanel: MenuBarOrganizerPanelController?
    private var secondaryPanel: MenuBarOrganizerPanelController?
    private var refreshTimer: Timer?
    private var rehideTimer: Timer?
    private var globalMouseMonitor: Any?
    private var globalScrollMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?
    private var editingCount = 0
    private var scrollAccumulator: CGFloat = 0
    private var undoRecord: UndoRecord?
    private var suppressUndo = false
    private var snapshotTask: Task<Void, Never>?
    private var imageCache: [MenuBarItemIdentity: NSImage] = [:]

    private struct UndoRecord {
        let itemID: MenuBarItemIdentity
        let previousSection: MenuBarOrganizerSection
        let previousRightNeighbor: MenuBarItemIdentity?
    }

    private init() {}

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = AppFeature.menuBarOrganizer.isAvailable
            && defaults.bool(forKey: DefaultsKey.menuBarOrganizerEnabled)
        if enabled {
            startIfNeeded()
            syncAlwaysHiddenDivider()
            syncHotkeys()
            installEventMonitors()
            applyDividerState()
            refresh()
        } else {
            stop()
        }
    }

    func stop() {
        guard isRunning else {
            hotkeys.unregisterAll()
            return
        }
        hiddenSectionShown = true
        alwaysHiddenSectionShown = true
        applyDividerState()
        searchPanel?.close()
        secondaryPanel?.close()
        refreshTimer?.invalidate()
        refreshTimer = nil
        snapshotTask?.cancel()
        snapshotTask = nil
        rehideTimer?.invalidate()
        rehideTimer = nil
        removeEventMonitors()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        hotkeys.unregisterAll()
        hiddenDivider?.removePreservingPosition()
        alwaysHiddenDivider?.removePreservingPosition()
        controlItem?.removePreservingPosition()
        hiddenDivider = nil
        alwaysHiddenDivider = nil
        controlItem = nil
        items = []
        undoRecord = nil
        canUndo = false
        isRunning = false
    }

    func beginEditing() {
        editingCount += 1
        guard isRunning else { return }
        hiddenSectionShown = true
        alwaysHiddenSectionShown = true
        cancelRehide()
        applyDividerState()
        refresh()
    }

    func endEditing() {
        editingCount = max(0, editingCount - 1)
        guard editingCount == 0 else { return }
        applyDividerState()
        scheduleRehide()
    }

    func completeSetup() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        editingCount = 0
        hiddenSectionShown = false
        alwaysHiddenSectionShown = false
        applyDividerState()
        refresh()
    }

    func refresh() {
        refresh(captureImages: UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerCapturePreviews))
    }

    func toggleHiddenSection() {
        guard isRunning else { return }
        if hiddenSectionShown || secondaryPanel?.isVisible == true {
            hideAll()
        } else {
            show(.hidden)
        }
    }

    func toggleAlwaysHiddenSection() {
        guard isRunning,
              UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled)
        else { return }
        if alwaysHiddenSectionShown {
            alwaysHiddenSectionShown = false
            applyDividerState()
        } else {
            show(.alwaysHidden)
        }
    }

    func showSearch() {
        guard isRunning else { return }
        refresh()
        if searchPanel == nil {
            searchPanel = MenuBarOrganizerPanelController(kind: .search, service: self)
        }
        searchPanel?.show()
    }

    func showSecondaryBar() {
        guard isRunning else { return }
        refresh()
        if secondaryPanel == nil {
            secondaryPanel = MenuBarOrganizerPanelController(kind: .secondary, service: self)
        }
        secondaryPanel?.show(anchor: controlItem?.frame)
        scheduleRehide()
    }

    func hideAll() {
        secondaryPanel?.close()
        hiddenSectionShown = false
        alwaysHiddenSectionShown = false
        applyDividerState()
        cancelRehide()
        refresh(captureImages: false)
    }

    func move(itemID: MenuBarItemIdentity,
              before targetID: MenuBarItemIdentity?,
              to section: MenuBarOrganizerSection) {
        Task { await performMove(itemID: itemID, before: targetID, to: section) }
    }

    func undoLastMove() {
        guard let record = undoRecord else { return }
        suppressUndo = true
        Task {
            await performMove(itemID: record.itemID,
                              before: record.previousRightNeighbor,
                              to: record.previousSection)
            suppressUndo = false
            undoRecord = nil
            canUndo = false
        }
    }

    func activate(itemID: MenuBarItemIdentity) {
        Task {
            guard let original = items.first(where: { $0.id == itemID }) else { return }
            searchPanel?.close()
            secondaryPanel?.close()
            if original.section != .visible {
                showInMenuBar(original.section)
                try? await Task.sleep(for: .milliseconds(140))
                refresh(captureImages: false)
            }
            guard let current = items.first(where: { $0.id == itemID }) else {
                operationMessage = MenuBarItemMoveError.itemUnavailable.localizedDescription
                return
            }
            do {
                try await mover.click(item: current)
                scheduleRehide()
            } catch {
                operationMessage = error.localizedDescription
            }
        }
    }

    func clearOperationMessage() {
        operationMessage = nil
    }

    private func startIfNeeded() {
        guard !isRunning else { return }
        let control = MenuBarDividerItem(kind: .control)
        let hidden = MenuBarDividerItem(kind: .hidden)
        control.onLeftClick = { [weak self] in self?.toggleHiddenSection() }
        control.onRightClick = { [weak self, weak control] in
            self?.showContextMenu(relativeTo: control)
        }
        hidden.onLeftClick = { [weak self] in self?.toggleHiddenSection() }
        controlItem = control
        hiddenDivider = hidden
        searchPanel = MenuBarOrganizerPanelController(kind: .search, service: self)
        secondaryPanel = MenuBarOrganizerPanelController(kind: .secondary, service: self)
        isRunning = true

        let setupComplete = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        hiddenSectionShown = !setupComplete
        alwaysHiddenSectionShown = !setupComplete
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(captureImages: false) }
        }
        refreshTimer?.tolerance = 0.5
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self,
                          MenuBarOrganizerRehideMode.sanitized(
                            UserDefaults.standard.string(forKey: DefaultsKey.menuBarOrganizerRehideMode)) == .focusedApp,
                          self.editingCount == 0,
                          self.searchPanel?.isVisible != true,
                          self.secondaryPanel?.isVisible != true,
                          !self.pointerIsInsideMenuBar()
                    else { return }
                    self.hideAll()
                }
            }
    }

    private func syncAlwaysHiddenDivider() {
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled)
        if enabled, alwaysHiddenDivider == nil {
            let divider = MenuBarDividerItem(kind: .alwaysHidden)
            divider.onLeftClick = { [weak self] in self?.toggleAlwaysHiddenSection() }
            alwaysHiddenDivider = divider
        } else if !enabled, let divider = alwaysHiddenDivider {
            alwaysHiddenSectionShown = true
            divider.setCollapsed(false, markerVisible: false, collapsedLength: 1)
            divider.removePreservingPosition()
            alwaysHiddenDivider = nil
        }
    }

    private func applyDividerState() {
        let defaults = UserDefaults.standard
        let setupComplete = defaults.bool(forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        let markers = editingCount > 0
            || !setupComplete
            || defaults.bool(forKey: DefaultsKey.menuBarOrganizerShowDividers)
        let length = MenuBarOrganizerSupport.collapsedLength(
            screenWidths: NSScreen.screens.map(\.frame.width))
        hiddenDivider?.setCollapsed(!hiddenSectionShown && editingCount == 0,
                                    markerVisible: markers,
                                    collapsedLength: length)
        alwaysHiddenDivider?.setCollapsed(!alwaysHiddenSectionShown && editingCount == 0,
                                          markerVisible: markers,
                                          collapsedLength: length)
    }

    private func refresh(captureImages: Bool) {
        guard isRunning else { return }
        let records = provider.records()
        let ownWindowIDs = Set([controlItem?.windowID, hiddenDivider?.windowID,
                                alwaysHiddenDivider?.windowID].compactMap { $0 })
        let filtered = records.filter { !ownWindowIDs.contains($0.windowID) }
        let identities = MenuBarOrganizerSupport.identities(for: filtered)
        let hiddenX = hiddenDivider?.frame?.midX
        let alwaysX = alwaysHiddenDivider?.frame?.midX
        items = filtered.compactMap { record in
            guard let identity = identities[record.windowID] else { return nil }
            let section = MenuBarOrganizerSupport.section(itemMidX: record.frame.midX,
                                                          hiddenDividerMidX: hiddenX,
                                                          alwaysHiddenDividerMidX: alwaysX)
            // Organizer-owned divider windows were removed by window id
            // above. Other Vorssaint status items (metrics, battery time)
            // are normal user-manageable items and must remain movable.
            let protected = false
            let immovable = MenuBarOrganizerSupport.isSystemImmovable(
                bundleIdentifier: record.bundleIdentifier, title: record.title)
            let fallbackIcon = NSRunningApplication(processIdentifier: record.ownerPID)
                .flatMap(\.bundleURL)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
            return ManagedMenuBarItem(id: identity,
                                      windowID: record.windowID,
                                      ownerPID: record.ownerPID,
                                      ownerName: record.ownerName,
                                      bundleIdentifier: record.bundleIdentifier,
                                      title: record.title,
                                      frame: record.frame,
                                      section: section,
                                      isMovable: !protected && !immovable,
                                      isProtected: protected,
                                      image: imageCache[identity] ?? fallbackIcon)
        }
        .sorted { $0.frame.minX < $1.frame.minX }
        capabilities = MenuBarOrganizerCapabilities(
            canEnumerate: true,
            canMove: AXIsProcessTrusted(),
            canCapture: CGPreflightScreenCaptureAccess(),
            hasPrivateFrameAPI: DynamicMenuBarAPI.shared.hasWindowFrame)
        if captureImages, capabilities.canCapture {
            loadSnapshots(records: filtered, identities: identities)
        }
    }

    private func performMove(itemID: MenuBarItemIdentity,
                             before targetID: MenuBarItemIdentity?,
                             to section: MenuBarOrganizerSection) async {
        operationMessage = nil
        guard targetID != itemID else { return }
        showInMenuBar(.alwaysHidden)
        try? await Task.sleep(for: .milliseconds(80))
        refresh(captureImages: false)
        guard let item = items.first(where: { $0.id == itemID }) else {
            operationMessage = MenuBarItemMoveError.itemUnavailable.localizedDescription
            return
        }

        let orderedBefore = MenuBarOrganizerSupport.orderedItems(items, in: item.section)
        let rightNeighbor = orderedBefore.drop(while: { $0.id != item.id }).dropFirst().first?.id
        if !suppressUndo {
            undoRecord = UndoRecord(itemID: item.id,
                                    previousSection: item.section,
                                    previousRightNeighbor: rightNeighbor)
        }

        let destination: (CGRect, Bool)?
        if let targetID, let target = items.first(where: { $0.id == targetID }) {
            destination = (target.frame, false)
        } else {
            destination = boundaryDestination(for: section, referenceFrame: item.frame)
        }
        guard let destination else {
            operationMessage = "The section divider is not available."
            return
        }

        do {
            try await mover.move(item: item,
                                 destinationFrame: destination.0,
                                 placeAfter: destination.1) { [weak self] in
                guard let self else { return false }
                self.refresh(captureImages: false)
                guard let current = self.items.first(where: { $0.id == itemID }) else { return false }
                if let targetID,
                   let target = self.items.first(where: { $0.id == targetID }) {
                    return current.section == section
                        && current.frame.maxX <= target.frame.minX + 3
                }
                return current.section == section
            }
            canUndo = undoRecord != nil
            refresh()
            scheduleRehide()
        } catch {
            operationMessage = error.localizedDescription
            if !suppressUndo {
                undoRecord = nil
                canUndo = false
            }
            refresh()
        }
    }

    private func boundaryDestination(for section: MenuBarOrganizerSection,
                                     referenceFrame: CGRect) -> (CGRect, Bool)? {
        // Divider windows expose AppKit frames while CGWindow records and
        // synthesized mouse events use Quartz coordinates. Their horizontal
        // axis is shared; copy only x/width and keep the item's Quartz y.
        func quartzBoundary(_ frame: CGRect, placeAfter: Bool) -> (CGRect, Bool) {
            (CGRect(x: frame.minX,
                    y: referenceFrame.minY,
                    width: frame.width,
                    height: referenceFrame.height),
             placeAfter)
        }
        switch section {
        case .visible:
            return hiddenDivider?.frame.map { quartzBoundary($0, placeAfter: true) }
        case .hidden:
            return hiddenDivider?.frame.map { quartzBoundary($0, placeAfter: false) }
        case .alwaysHidden:
            return alwaysHiddenDivider?.frame.map { quartzBoundary($0, placeAfter: false) }
        }
    }

    private func show(_ section: MenuBarOrganizerSection) {
        if editingCount == 0, shouldPresentInSecondaryBar(section: section) {
            showSecondaryBar()
            return
        }
        showInMenuBar(section)
        scheduleRehide()
    }

    private func showInMenuBar(_ section: MenuBarOrganizerSection) {
        switch section {
        case .visible:
            break
        case .hidden:
            hiddenSectionShown = true
        case .alwaysHidden:
            hiddenSectionShown = true
            alwaysHiddenSectionShown = true
        }
        applyDividerState()
        refresh(captureImages: false)
    }

    private func shouldPresentInSecondaryBar(section: MenuBarOrganizerSection) -> Bool {
        let mode = MenuBarOrganizerPresentationMode.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.menuBarOrganizerPresentationMode))
        let width = items.filter { item in
            section == .alwaysHidden ? item.section != .visible : item.section == .hidden
        }.reduce(CGFloat(0)) { $0 + $1.frame.width }
        let screen = controlItem?.frame.flatMap { frame in
            NSScreen.screens.first { $0.frame.intersects(frame) }
        } ?? NSScreen.main
        let available = (screen?.visibleFrame.width ?? 1_024) * 0.45
        let hasNotch = screen?.auxiliaryTopLeftArea != nil || screen?.auxiliaryTopRightArea != nil
        return MenuBarOrganizerSupport.shouldUseSecondaryBar(
            mode: mode, hiddenWidth: width, availableWidth: available, hasNotch: hasNotch)
    }

    private func scheduleRehide() {
        cancelRehide()
        guard editingCount == 0,
              MenuBarOrganizerRehideMode.sanitized(
                UserDefaults.standard.string(forKey: DefaultsKey.menuBarOrganizerRehideMode)) == .afterDelay
        else { return }
        let seconds = MenuBarOrganizerSupport.sanitizedRehideDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.menuBarOrganizerRehideDelay))
        rehideTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) {
            [weak self] _ in
            Task { @MainActor in
                guard let self, !self.pointerIsInsideMenuBar() else {
                    self?.scheduleRehide()
                    return
                }
                self.hideAll()
            }
        }
    }

    private func cancelRehide() {
        rehideTimer?.invalidate()
        rehideTimer = nil
    }

    private func installEventMonitors() {
        removeEventMonitors()
        let defaults = UserDefaults.standard
        let hover = defaults.bool(forKey: DefaultsKey.menuBarOrganizerShowOnHover)
        let emptyClick = defaults.bool(forKey: DefaultsKey.menuBarOrganizerShowOnEmptyClick)
        if hover || emptyClick {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
                DispatchQueue.main.async {
                    guard let self, self.isRunning else { return }
                    if event.type == .mouseMoved, hover {
                        if self.pointerIsInsideMenuBar() {
                            if !self.hiddenSectionShown { self.show(.hidden) }
                        } else if self.hiddenSectionShown {
                            self.scheduleRehide()
                        }
                    } else if event.type == .leftMouseDown, emptyClick,
                              self.pointerIsInsideMenuBar(),
                              !self.pointerIsOverManagedItem() {
                        self.toggleHiddenSection()
                    }
                }
            }
        }
        if defaults.bool(forKey: DefaultsKey.menuBarOrganizerShowOnScroll) {
            globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                DispatchQueue.main.async {
                    guard let self, self.pointerIsInsideMenuBar() else { return }
                    self.scrollAccumulator += event.scrollingDeltaY + event.scrollingDeltaX
                    if abs(self.scrollAccumulator) >= 8 {
                        self.scrollAccumulator = 0
                        self.toggleHiddenSection()
                    }
                }
            }
        }
    }

    private func removeEventMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let globalScrollMonitor { NSEvent.removeMonitor(globalScrollMonitor) }
        globalMouseMonitor = nil
        globalScrollMonitor = nil
    }

    private func pointerIsInsideMenuBar() -> Bool {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return false }
        let height = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return point.y >= screen.frame.maxY - height - 2
    }

    private func pointerIsOverManagedItem() -> Bool {
        guard let point = CGEvent(source: nil)?.location else { return false }
        return provider.records().contains { $0.frame.contains(point) }
    }

    private func syncHotkeys() {
        let defaults = UserDefaults.standard
        hotkeys.sync(registrations: [
            (.toggleHidden,
             defaults.bool(forKey: DefaultsKey.menuBarOrganizerToggleShortcutEnabled),
             GlobalShortcut.saved(for: DefaultsKey.menuBarOrganizerToggleShortcut,
                                  fallback: .menuBarOrganizerToggleDefault),
             { [weak self] in self?.toggleHiddenSection() }),
            (.toggleAlwaysHidden,
             defaults.bool(forKey: DefaultsKey.menuBarOrganizerAlwaysShortcutEnabled),
             GlobalShortcut.saved(for: DefaultsKey.menuBarOrganizerAlwaysShortcut,
                                  fallback: .menuBarOrganizerAlwaysDefault),
             { [weak self] in self?.toggleAlwaysHiddenSection() }),
            (.search,
             defaults.bool(forKey: DefaultsKey.menuBarOrganizerSearchShortcutEnabled),
             GlobalShortcut.saved(for: DefaultsKey.menuBarOrganizerSearchShortcut,
                                  fallback: .menuBarOrganizerSearchDefault),
             { [weak self] in self?.showSearch() }),
        ])
        hotkeyRegistrationFailed = hotkeys.registrationFailed
    }

    private func loadSnapshots(records: [MenuBarOrganizerWindowRecord],
                               identities: [CGWindowID: MenuBarItemIdentity]) {
        snapshotTask?.cancel()
        let missing = records.filter {
            guard let identity = identities[$0.windowID] else { return false }
            return imageCache[identity] == nil
        }
        guard !missing.isEmpty else { return }
        snapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for record in missing {
                guard !Task.isCancelled,
                      let identity = identities[record.windowID],
                      let image = await provider.image(for: record.windowID)
                else { continue }
                imageCache[identity] = image
                if let index = items.firstIndex(where: { $0.id == identity }) {
                    let item = items[index]
                    items[index] = ManagedMenuBarItem(
                        id: item.id, windowID: item.windowID, ownerPID: item.ownerPID,
                        ownerName: item.ownerName, bundleIdentifier: item.bundleIdentifier,
                        title: item.title, frame: item.frame, section: item.section,
                        isMovable: item.isMovable, isProtected: item.isProtected, image: image)
                }
            }
        }
    }

    private func showContextMenu(relativeTo item: MenuBarDividerItem?) {
        guard let button = item?.statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: hiddenSectionShown ? "Hide hidden items" : "Show hidden items",
                     action: #selector(contextToggleHidden),
                     keyEquivalent: "")
        if UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled) {
            menu.addItem(withTitle: alwaysHiddenSectionShown ? "Hide always-hidden items" : "Show always-hidden items",
                         action: #selector(contextToggleAlways),
                         keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Search menu bar items",
                     action: #selector(contextSearch),
                     keyEquivalent: "")
        menu.addItem(withTitle: "Show secondary bar",
                     action: #selector(contextSecondary),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Menu Bar Settings…",
                     action: #selector(contextSettings),
                     keyEquivalent: "")
        for menuItem in menu.items { menuItem.target = self }
        item?.statusItem.menu = menu
        button.performClick(nil)
        DispatchQueue.main.async { item?.statusItem.menu = nil }
    }

    @objc private func contextToggleHidden() { toggleHiddenSection() }
    @objc private func contextToggleAlways() { toggleAlwaysHiddenSection() }
    @objc private func contextSearch() { showSearch() }
    @objc private func contextSecondary() { showSecondaryBar() }
    @objc private func contextSettings() {
        SettingsRouter.shared.page = .menuBarOrganizer
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
}
