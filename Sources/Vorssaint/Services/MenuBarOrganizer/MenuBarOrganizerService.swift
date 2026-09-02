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
        canEnumerate: false,
        canMove: AXIsProcessTrusted(),
        hasPrivateWindowList: false,
        unresolvedItemCount: 0,
        moveAvailabilityCounts: MenuBarOrganizerSupport.moveAvailabilityCounts(for: []))
    @Published private(set) var isRunning = false
    @Published private(set) var hiddenSectionShown = true
    @Published private(set) var alwaysHiddenSectionShown = true
    @Published private(set) var operationMessage: String?
    @Published private(set) var canUndo = false
    @Published private(set) var conflictingManagers: [MenuBarManagerDetection.RunningManager] = []

    private let provider = MenuBarWindowProvider()
    private let mover = MenuBarItemMover()
    private var controlItem: MenuBarDividerItem?
    private var hiddenDivider: MenuBarDividerItem?
    private var alwaysHiddenDivider: MenuBarDividerItem?
    private var secondaryPanel: MenuBarOrganizerPanelController?
    private var searchPanel: MenuBarOrganizerSearchPanelController?
    private let hotkeys = MenuBarOrganizerHotkeyService()
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?
    private var rehideTask: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var eventMonitors: [Any] = []
    private var menuTracking = false
    private var editingCount = 0
    private var preEditingState: (hidden: Bool, always: Bool)?
    private var undoRecord: UndoRecord?
    private var suppressUndo = false
    // Last-known midX of each divider while it was narrow (a real section
    // boundary). When the divider is collapsed to 4096 px its live frame.midX
    // shifts far to the right and stops being a meaningful boundary — we
    // fall back to this cached value so section attribution stays synchronised
    // with what the user actually sees on the menu bar.
    private var stableHiddenDividerMidX: CGFloat?
    private var stableAlwaysHiddenDividerMidX: CGFloat?

    private struct UndoRecord {
        let itemID: MenuBarItemIdentity
        let previousSection: MenuBarOrganizerSection
        let previousRightNeighbor: MenuBarItemIdentity?
    }

    private init() {}

    func syncWithPreferences() {
        // Never touch the WindowServer probes on systems the feature does not
        // support yet: macOS 27 crashes on enable, so even defaults carried
        // over from an older OS must stay inert.
        guard AppFeature.menuBarOrganizer.isSupportedOnCurrentSystem else {
            stop()
            return
        }
        let enabled = AppFeature.menuBarOrganizer.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerEnabled)
        conflictingManagers = MenuBarManagerDetection.runningManagers()
        guard enabled else {
            stop()
            return
        }
        guard conflictingManagers.isEmpty else {
            stop(preservingDiagnostics: true)
            return
        }
        guard AXIsProcessTrusted() else {
            stop(preservingDiagnostics: true)
            capabilities = MenuBarOrganizerCapabilities(
                canEnumerate: capabilities.canEnumerate,
                canMove: false,
                hasPrivateWindowList: capabilities.hasPrivateWindowList,
                unresolvedItemCount: capabilities.unresolvedItemCount,
                moveAvailabilityCounts: capabilities.moveAvailabilityCounts)
            return
        }

        startIfNeeded()
        syncAlwaysHiddenDivider()
        hotkeys.sync(actions: [
            .menuBarShowHidden: { [weak self] in self?.showHidden() },
            .menuBarShowAll: { [weak self] in self?.showAll() },
            .menuBarHideAll: { [weak self] in self?.hideAll() },
            .menuBarSearch: { [weak self] in self?.openSearch() },
            .menuBarSecondaryBar: { [weak self] in self?.showSecondaryBar() },
        ])
        installRevealMonitors()
        applyDividerState()
        refresh()
    }

    func stop() {
        stop(preservingDiagnostics: false)
    }

    func beginEditing() {
        editingCount += 1
        guard editingCount == 1, isRunning else { return }
        preEditingState = (hiddenSectionShown, alwaysHiddenSectionShown)
        hiddenSectionShown = true
        alwaysHiddenSectionShown = true
        secondaryPanel?.close()
        applyDividerState()
        scheduleRefreshTimer()
        refresh()
    }

    func endEditing() {
        editingCount = max(0, editingCount - 1)
        guard editingCount == 0 else { return }
        if UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerSetupComplete),
           let preEditingState {
            hiddenSectionShown = preEditingState.hidden
            alwaysHiddenSectionShown = preEditingState.always
        }
        preEditingState = nil
        applyDividerState()
        scheduleRefreshTimer()
        refresh()
    }

    func completeSetup() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        editingCount = 0
        preEditingState = nil
        hideAll()
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            _ = await self?.refreshNow()
        }
    }

    func retryStart() {
        conflictingManagers = MenuBarManagerDetection.runningManagers()
        syncWithPreferences()
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
              UserDefaults.standard.bool(
                forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled)
        else { return }
        if alwaysHiddenSectionShown || secondaryPanel?.isVisible == true {
            alwaysHiddenSectionShown = false
            secondaryPanel?.close()
            applyDividerState()
            refresh()
        } else {
            show(.alwaysHidden)
        }
    }

    func showSecondaryBar() {
        guard isRunning else { return }
        refresh()
        if secondaryPanel == nil {
            secondaryPanel = MenuBarOrganizerPanelController(service: self)
        }
        secondaryPanel?.show(anchor: controlItem?.frame)
        scheduleAutoRehide()
    }

    func showHidden() {
        guard isRunning else { return }
        show(.hidden)
    }

    func showAll() {
        guard isRunning else { return }
        show(.alwaysHidden)
    }

    func openSearch() {
        guard isRunning else { return }
        if searchPanel == nil {
            searchPanel = MenuBarOrganizerSearchPanelController(service: self)
        }
        searchPanel?.show(anchor: controlItem?.frame)
    }

    func searchItems(query: String) -> [ManagedMenuBarItem] {
        MenuBarOrganizerAdvancedSupport.search(query, items: items)
    }

    var secondaryBarSpacing: CGFloat {
        let preset = MenuBarSpacingPreset(rawValue: UserDefaults.standard.string(
            forKey: DefaultsKey.menuBarOrganizerSpacingPreset) ?? "") ?? .standard
        let custom = UserDefaults.standard.double(forKey: DefaultsKey.menuBarOrganizerCustomSpacing)
        return CGFloat(MenuBarOrganizerAdvancedSupport.effectiveSpacing(
            preset: preset, custom: custom))
    }

    func hideAll() {
        rehideTask?.cancel()
        rehideTask = nil
        secondaryPanel?.close()
        hiddenSectionShown = false
        alwaysHiddenSectionShown = false
        applyDividerState()
        refresh()
    }

    func move(itemID: MenuBarItemIdentity,
              before targetID: MenuBarItemIdentity?,
              to section: MenuBarOrganizerSection) {
        guard !mover.isMoving else {
            operationMessage = moveErrorMessage(.busy)
            return
        }
        Task { [weak self] in
            await self?.performMove(itemID: itemID, before: targetID, to: section)
        }
    }

    func undoLastMove() {
        guard let record = undoRecord else { return }
        suppressUndo = true
        Task { [weak self] in
            guard let self else { return }
            await performMove(itemID: record.itemID,
                              before: record.previousRightNeighbor,
                              to: record.previousSection)
            suppressUndo = false
            undoRecord = nil
            canUndo = false
        }
    }

    func activate(itemID: MenuBarItemIdentity) {
        Task { [weak self] in
            guard let self,
                  let original = items.first(where: { $0.id == itemID })
            else { return }
            secondaryPanel?.close()
            searchPanel?.close()
            if original.section != .visible {
                showInMenuBar(original.section)
                try? await Task.sleep(for: .milliseconds(160))
                _ = await refreshNow()
            }
            guard let current = items.first(where: { $0.id == itemID }) else {
                operationMessage = moveErrorMessage(.itemUnavailable)
                return
            }
            do {
                try await mover.click(item: current)
            } catch let error as MenuBarItemMoveError {
                operationMessage = moveErrorMessage(error)
            } catch {
                operationMessage = error.localizedDescription
            }
        }
    }

    func clearOperationMessage() {
        operationMessage = nil
    }

    private func startIfNeeded() {
        guard !isRunning else {
            scheduleRefreshTimer()
            return
        }
        teardownTask?.cancel()
        teardownTask = nil
        let control = MenuBarDividerItem(kind: .control)
        let hidden = MenuBarDividerItem(kind: .hidden)
        control.onLeftClick = { [weak self] in self?.toggleHiddenSection() }
        control.onRightClick = { [weak self, weak control] in
            self?.showContextMenu(relativeTo: control)
        }
        hidden.onLeftClick = { [weak self] in self?.toggleHiddenSection() }
        controlItem = control
        hiddenDivider = hidden
        secondaryPanel = MenuBarOrganizerPanelController(service: self)
        isRunning = true

        let setupComplete = UserDefaults.standard.bool(
            forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        hiddenSectionShown = !setupComplete
        alwaysHiddenSectionShown = !setupComplete
        installObservers()
        installRevealMonitors()
        scheduleRefreshTimer()
    }

    private func stop(preservingDiagnostics: Bool) {
        refreshTask?.cancel()
        refreshTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        removeObservers()
        removeRevealMonitors()
        rehideTask?.cancel()
        rehideTask = nil
        hotkeys.stop()
        secondaryPanel?.close()
        secondaryPanel = nil
        searchPanel?.close()
        searchPanel = nil
        editingCount = 0
        preEditingState = nil
        undoRecord = nil
        canUndo = false
        stableHiddenDividerMidX = nil
        stableAlwaysHiddenDividerMidX = nil

        guard isRunning || controlItem != nil || hiddenDivider != nil
                || alwaysHiddenDivider != nil
        else {
            if !preservingDiagnostics {
                items = []
                conflictingManagers = []
            }
            return
        }

        hiddenSectionShown = true
        alwaysHiddenSectionShown = true
        hiddenDivider?.expandForRemoval()
        alwaysHiddenDivider?.expandForRemoval()
        let removing = [controlItem, hiddenDivider, alwaysHiddenDivider].compactMap { $0 }
        controlItem = nil
        hiddenDivider = nil
        alwaysHiddenDivider = nil
        isRunning = false
        items = []

        teardownTask?.cancel()
        teardownTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            removing.forEach { $0.removePreservingPosition() }
        }
        if !preservingDiagnostics {
            conflictingManagers = []
            capabilities = MenuBarOrganizerCapabilities(
                canEnumerate: false,
                canMove: AXIsProcessTrusted(),
                hasPrivateWindowList: false,
                unresolvedItemCount: 0,
                moveAvailabilityCounts: MenuBarOrganizerSupport.moveAvailabilityCounts(for: []))
        }
    }

    private func syncAlwaysHiddenDivider() {
        let enabled = UserDefaults.standard.bool(
            forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled)
        if enabled, alwaysHiddenDivider == nil {
            let divider = MenuBarDividerItem(kind: .alwaysHidden)
            divider.onLeftClick = { [weak self] in self?.toggleAlwaysHiddenSection() }
            alwaysHiddenDivider = divider
        } else if !enabled, let divider = alwaysHiddenDivider {
            alwaysHiddenSectionShown = true
            divider.expandForRemoval()
            alwaysHiddenDivider = nil
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                divider.removePreservingPosition()
            }
        }
    }

    private func applyDividerState() {
        let setupComplete = UserDefaults.standard.bool(
            forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        let markers = editingCount > 0
            || !setupComplete
            || UserDefaults.standard.bool(
                forKey: DefaultsKey.menuBarOrganizerShowDividers)
        let length = MenuBarOrganizerSupport.collapsedLength(
            screenWidths: NSScreen.screens.map(\.frame.width))
        hiddenDivider?.setCollapsed(
            !hiddenSectionShown,
            markerVisible: markers,
            collapsedLength: length)
        alwaysHiddenDivider?.setCollapsed(
            !alwaysHiddenSectionShown,
            markerVisible: markers,
            collapsedLength: length)
    }

    @discardableResult
    private func refreshNow() async -> MenuBarItemSnapshot? {
        guard isRunning else { return nil }
        let excluded = Set([
            controlItem?.windowID,
            hiddenDivider?.windowID,
            alwaysHiddenDivider?.windowID,
        ].compactMap { $0 })
        let hiddenMidX = stableDividerMidX(
            for: hiddenDivider, cache: &stableHiddenDividerMidX)
        let alwaysHiddenMidX = stableDividerMidX(
            for: alwaysHiddenDivider, cache: &stableAlwaysHiddenDividerMidX)
        let snapshot = await provider.snapshot(
            hiddenDividerMidX: hiddenMidX,
            alwaysHiddenDividerMidX: alwaysHiddenMidX,
            excludedWindowIDs: excluded)
        guard !Task.isCancelled, isRunning else { return nil }
        capabilities = snapshot.capabilities
        if !MenuBarOrganizerSupport.shouldKeepPreviousSnapshot(
            previousCount: items.count,
            newCount: snapshot.items.count,
            enumerationSucceeded: snapshot.enumerationSucceeded) {
            // Sticky source metadata: when a windowID persists but the fresh
            // AX scan momentarily lost the item's source app (timeout, apps
            // busy, cache miss), keep the previously-resolved source instead
            // of downgrading. Prevents the pill flicker where an item drops
            // to an unidentified placeholder for one refresh, then reappears.
            let previousByWindow = Dictionary(
                uniqueKeysWithValues: items.map { ($0.windowID, $0) })
            let stabilized = snapshot.items.map { current -> ManagedMenuBarItem in
                guard let previous = previousByWindow[current.windowID] else {
                    return current
                }
                let currentUnknown = current.sourcePID == nil
                    || current.bundleIdentifier
                        == MenuBarOrganizerSupport.controlCenterBundleIdentifier
                let previousKnown = previous.sourcePID != nil
                    && previous.bundleIdentifier
                        != MenuBarOrganizerSupport.controlCenterBundleIdentifier
                guard currentUnknown, previousKnown else { return current }
                return ManagedMenuBarItem(
                    id: previous.id,
                    windowID: current.windowID,
                    ownerPID: current.ownerPID,
                    ownerBundleIdentifier: current.ownerBundleIdentifier,
                    sourcePID: previous.sourcePID,
                    ownerName: previous.ownerName,
                    sourceName: previous.sourceName,
                    bundleIdentifier: previous.bundleIdentifier,
                    title: previous.title.isEmpty ? current.title : previous.title,
                    frame: current.frame,
                    section: current.section,
                    identityState: previous.identityState,
                    isMovable: current.isMovable,
                    isProtected: current.isProtected,
                    image: previous.image ?? current.image)
            }
            // Carry forward items from non-visible sections that temporarily
            // vanish entirely from the snapshot. Use semantic matching (not
            // just windowID equality) so a recreated window doesn't leave the
            // old carried entry behind. Also dedupe within the carried set to
            // prevent accumulation across successive refreshes.
            let carried = items.reduce(into: [ManagedMenuBarItem]()) { acc, previous in
                guard previous.section != .visible else { return }
                let identityIsUsable = previous.identityState == .stable
                    || (previous.sourcePID != nil
                        && previous.bundleIdentifier
                            != MenuBarOrganizerSupport.controlCenterBundleIdentifier)
                guard identityIsUsable else { return }
                let inFresh = MenuBarOrganizerSupport.equivalentItem(
                    to: previous, in: stabilized, requiringFrameProximity: false) != nil
                let alreadyCarried = MenuBarOrganizerSupport.equivalentItem(
                    to: previous, in: acc, requiringFrameProximity: false) != nil
                guard !inFresh, !alreadyCarried else { return }
                acc.append(previous)
            }
            items = stabilized + carried
        }
        return snapshot
    }

    private func performMove(itemID: MenuBarItemIdentity,
                             before targetID: MenuBarItemIdentity?,
                             to section: MenuBarOrganizerSection) async {
        operationMessage = nil
        guard targetID != itemID else { return }
        guard MenuBarManagerDetection.runningManagers().isEmpty else {
            conflictingManagers = MenuBarManagerDetection.runningManagers()
            operationMessage = moveErrorMessage(.busy)
            return
        }

        showInMenuBar(.alwaysHidden)
        try? await Task.sleep(for: .milliseconds(350))
        await provider.invalidateIdentityCache()
        _ = await refreshNow()
        guard let original = MenuBarOrganizerSupport.item(matching: itemID, in: items) else {
            operationMessage = moveErrorMessage(.itemUnavailable)
            return
        }
        if let targetID,
           MenuBarOrganizerSupport.item(matching: targetID, in: items) == nil {
            operationMessage = moveErrorMessage(.itemUnavailable)
            return
        }
        let movingItemID = original.id
        let baselineItems = items

        let orderedBefore = MenuBarOrganizerSupport.orderedItems(items, in: original.section)
        let rightNeighbor = orderedBefore
            .drop(while: { $0.id != original.id })
            .dropFirst()
            .first?.id
        if !suppressUndo {
            undoRecord = UndoRecord(itemID: original.id,
                                    previousSection: original.section,
                                    previousRightNeighbor: rightNeighbor)
        }

        var lastError: MenuBarItemMoveError = .verificationFailed
        for attempt in 0..<3 {
            guard let snapshot = await refreshNow(), snapshot.enumerationSucceeded,
                  let current = MenuBarOrganizerSupport.equivalentItem(
                    to: original,
                    in: items,
                    requiringFrameProximity: false) else {
                lastError = .itemUnavailable
                break
            }
            guard targetID == nil || MenuBarOrganizerSupport.item(
                matching: targetID!, in: items)?.section == section else {
                lastError = .itemUnavailable
                break
            }
            let targetWindowID = targetID.flatMap { id in
                MenuBarOrganizerSupport.item(matching: id, in: items)?.windowID
            }
            guard let destination = destination(
                for: section,
                targetWindowID: targetWindowID,
                referenceFrame: current.frame)
            else {
                lastError = .itemUnavailable
                break
            }
            do {
                try await mover.move(item: current,
                                     destinationFrame: destination.frame,
                                     placeAfter: destination.placeAfter)
                try? await Task.sleep(for: .milliseconds(300 + attempt * 200))
                guard let snapshot = await refreshNow(), snapshot.enumerationSucceeded else {
                    lastError = .itemUnavailable
                    break
                }
                // Fast-path: the moved item's WindowServer window persists
                // through a Cmd-drag, so if that windowID is now in the
                // destination section, the move succeeded. Accept even if
                // Control Center reflowed adjacent items — retrying would
                // cause the visible "sobe/desce" bug where each attempt
                // Cmd-drags the item again.
                if let movedItem = items.first(where: { $0.windowID == current.windowID }),
                   movedItem.section == section {
                    canUndo = undoRecord != nil
                    return
                }
                // Slow-path: windowID vanished or landed in the wrong section.
                // Use the strict identity-based verification as a secondary
                // signal before conceding.
                if MenuBarOrganizerSupport.isSingleItemMove(
                    before: baselineItems,
                    after: items,
                    movingItemID: movingItemID,
                    destination: section),
                   let movedItem = MenuBarOrganizerSupport.equivalentItem(
                       to: original,
                       in: items,
                       requiringFrameProximity: false),
                   moveWasVerified(item: movedItem,
                                  targetItemID: targetID,
                                  section: section) {
                    canUndo = undoRecord != nil
                    return
                }
                lastError = .verificationFailed
            } catch let error as MenuBarItemMoveError {
                lastError = error
                if error != .verificationFailed { break }
            } catch {
                operationMessage = error.localizedDescription
                break
            }
        }

        operationMessage = moveErrorMessage(lastError)
        if !suppressUndo {
            undoRecord = nil
            canUndo = false
        }
        _ = await refreshNow()
    }

    /// Return a section-boundary midX that stays put when the divider is
    /// collapsed to its 4096 px length. A "narrow enough" frame width means
    /// the marker chevron is at a real position; anything wider is a
    /// collapse and we return the last-known narrow midX instead.
    private func stableDividerMidX(for divider: MenuBarDividerItem?,
                                   cache: inout CGFloat?) -> CGFloat? {
        guard let frame = divider?.frame else { return cache }
        // NSStatusItem.squareLength is ~22 pt. Any frame narrower than 64 pt
        // is a real, uncollapsed marker whose midX is a valid boundary.
        if frame.width <= 64 {
            cache = frame.midX
            return frame.midX
        }
        return cache
    }

    private func destination(for section: MenuBarOrganizerSection,
                             targetWindowID: CGWindowID?,
                             referenceFrame: CGRect) -> (frame: CGRect, placeAfter: Bool)? {
        if let targetWindowID,
           let target = items.first(where: { $0.windowID == targetWindowID }) {
            return (target.frame, false)
        }
        func quartzFrame(_ frame: CGRect, placeAfter: Bool) -> (CGRect, Bool) {
            (CGRect(x: frame.minX,
                    y: referenceFrame.minY,
                    width: frame.width,
                    height: referenceFrame.height),
             placeAfter)
        }
        switch section {
        case .visible:
            return hiddenDivider?.frame.map { quartzFrame($0, placeAfter: true) }
        case .hidden:
            // Anchor to the alwaysHiddenDivider (drop just to its right) so
            // the item lands solidly inside the hidden section between the
            // two dividers, even when that section is empty and the dividers
            // sit adjacent. Falls back to hiddenDivider.minX - 2 when the
            // always-hidden section is disabled.
            if let frame = alwaysHiddenDivider?.frame {
                return quartzFrame(frame, placeAfter: true)
            }
            return hiddenDivider?.frame.map { quartzFrame($0, placeAfter: false) }
        case .alwaysHidden:
            return alwaysHiddenDivider?.frame.map { quartzFrame($0, placeAfter: false) }
        }
    }

    private func moveWasVerified(item: ManagedMenuBarItem,
                                 targetItemID: MenuBarItemIdentity?,
                                 section: MenuBarOrganizerSection) -> Bool {
        guard item.section == section else { return false }
        guard let targetItemID,
              let target = MenuBarOrganizerSupport.item(
                matching: targetItemID,
                in: items)
        else { return targetItemID == nil }
        return item.frame.maxX <= target.frame.minX + 3
    }

    private func show(_ section: MenuBarOrganizerSection) {
        let mode = MenuBarOrganizerPresentationMode.sanitized(
            UserDefaults.standard.string(
                forKey: DefaultsKey.menuBarOrganizerPresentationMode))
        let hiddenWidth = items.filter {
            section == .alwaysHidden ? $0.section != .visible : $0.section == .hidden
        }.reduce(CGFloat(0)) { $0 + $1.frame.width }
        let screen = controlItem?.frame.flatMap { frame in
            NSScreen.screens.first { $0.frame.intersects(frame) }
        } ?? NSScreen.main
        let availableWidth = (screen?.visibleFrame.width ?? 1_024) * 0.45
        let hasNotch = screen?.auxiliaryTopLeftArea != nil
            || screen?.auxiliaryTopRightArea != nil
        if MenuBarOrganizerSupport.shouldUseSecondaryBar(
            mode: mode,
            hiddenWidth: hiddenWidth,
            availableWidth: availableWidth,
            hasNotch: hasNotch) {
            showSecondaryBar()
        } else {
            showInMenuBar(section)
        }
    }

    private func showInMenuBar(_ section: MenuBarOrganizerSection) {
        secondaryPanel?.close()
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
        refresh()
        scheduleAutoRehide()
    }

    private func scheduleAutoRehide() {
        rehideTask?.cancel()
        guard isRunning, editingCount == 0 else { return }
        let policy = MenuBarRehidePolicy.fromStorage(UserDefaults.standard.string(
            forKey: DefaultsKey.menuBarOrganizerAutoRehidePolicy))
        guard !UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerSecondaryBarPinned) else {
            return
        }
        guard case .afterSeconds(let seconds) = policy else { return }
        guard hiddenSectionShown || alwaysHiddenSectionShown || secondaryPanel?.isVisible == true else {
            return
        }
        rehideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.rehideIfSafe() }
        }
    }

    private func rehideIfSafe() {
        guard isRunning else { return }
        let pointerInside = managedSurfaceContains(NSEvent.mouseLocation)
        let pressed = NSEvent.pressedMouseButtons != 0
        let shouldHide = MenuBarOrganizerAdvancedSupport.shouldRehide(
            now: Date(), deadline: Date(), pointerInside: pointerInside,
            menuOpen: menuTracking, interactionInProgress: pressed)
        guard shouldHide else {
            scheduleAutoRehide()
            return
        }
        hideAll()
    }

    private func installRevealMonitors() {
        removeRevealMonitors()
        let defaults = UserDefaults.standard
        let hover = defaults.bool(forKey: DefaultsKey.menuBarOrganizerHoverRevealEnabled)
        let emptyArea = defaults.bool(forKey: DefaultsKey.menuBarOrganizerEmptyAreaRevealEnabled)
        let scroll = defaults.bool(forKey: DefaultsKey.menuBarOrganizerScrollRevealEnabled)
        let hasClickOutside = MenuBarRehidePolicy.fromStorage(defaults.string(
            forKey: DefaultsKey.menuBarOrganizerAutoRehidePolicy)) == .clickOutside
        guard hover || emptyArea || scroll || hasClickOutside else { return }

        if hover {
            eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
                [weak self] event in
                Task { @MainActor in self?.handleMouseMoved(event) }
            } as Any)
        }
        if scroll {
            eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                Task { @MainActor in self?.handleScroll(event) }
            } as Any)
        }
        if emptyArea || hasClickOutside {
            eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
                [weak self] event in
                Task { @MainActor in self?.handleMouseDown(event) }
            } as Any)
        }
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) {
            [weak self] event in
            Task { @MainActor in self?.handleLocalMouse(event) }
            return event
        } as Any)
    }

    private func removeRevealMonitors() {
        for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
        eventMonitors.removeAll()
    }

    private func handleMouseMoved(_ event: NSEvent) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerHoverRevealEnabled),
              isMenuBarPoint(event) else { return }
        showHidden()
    }

    private func handleScroll(_ event: NSEvent) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerScrollRevealEnabled),
              isMenuBarPoint(event) else { return }
        showHidden()
    }

    private func handleMouseDown(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        if UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerEmptyAreaRevealEnabled),
           isMenuBarPoint(event), !managedSurfaceContains(point) {
            showHidden()
            return
        }
        if MenuBarRehidePolicy.fromStorage(UserDefaults.standard.string(
            forKey: DefaultsKey.menuBarOrganizerAutoRehidePolicy)) == .clickOutside,
           !managedSurfaceContains(point) {
            hideAll()
        }
    }

    private func handleLocalMouse(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            handleMouseDown(event)
        } else if event.type == .leftMouseUp {
            scheduleAutoRehide()
        }
    }

    private func isMenuBarPoint(_ event: NSEvent) -> Bool {
        let point = event.locationInWindow
        let global = event.window?.convertPoint(toScreen: point) ?? NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            global.x >= screen.frame.minX && global.x <= screen.frame.maxX
                && global.y >= screen.frame.maxY - 48 && global.y <= screen.frame.maxY + 2
        }
    }

    private func managedSurfaceContains(_ point: CGPoint) -> Bool {
        if controlItem?.frame?.contains(point) == true || hiddenDivider?.frame?.contains(point) == true
            || alwaysHiddenDivider?.frame?.contains(point) == true {
            return true
        }
        return secondaryPanel?.contains(point: point) == true || searchPanel?.contains(point: point) == true
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        guard isRunning else {
            refreshTimer = nil
            return
        }
        // Pause the periodic timer while the user is editing. The editor
        // refreshes explicitly (open, "Atualizar" button, post-move) and via
        // workspace notifications (app launch/quit). Continuous polling only
        // caused AX-scan flicker without any user benefit.
        guard editingCount == 0 else {
            refreshTimer = nil
            return
        }
        let interval: TimeInterval = 10
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func installObservers() {
        removeObservers()
        func observe(_ center: NotificationCenter,
                     _ name: Notification.Name,
                     action: @escaping @MainActor () -> Void) {
            let token = center.addObserver(
                forName: name, object: nil, queue: .main) { _ in
                    Task { @MainActor in action() }
                }
            observers.append((center, token))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { [weak self] in
            guard let self else { return }
            conflictingManagers = MenuBarManagerDetection.runningManagers()
            guard conflictingManagers.isEmpty else {
                stop(preservingDiagnostics: true)
                return
            }
            refresh()
        }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { [weak self] in
            self?.conflictingManagers = MenuBarManagerDetection.runningManagers()
            self?.refresh()
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            Task { await self?.provider.invalidateIdentityCache() }
            self?.refresh()
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            Task { await self?.provider.invalidateIdentityCache() }
            self?.refresh()
        }
        observe(.default, NSMenu.didBeginTrackingNotification) { [weak self] in
            self?.menuTracking = true
            self?.rehideTask?.cancel()
        }
        observe(.default, NSMenu.didEndTrackingNotification) { [weak self] in
            self?.menuTracking = false
            self?.scheduleAutoRehide()
        }
    }

    private func removeObservers() {
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
    }

    private func showContextMenu(relativeTo item: MenuBarDividerItem?) {
        guard let button = item?.statusItem.button else { return }
        let text = FeatureStrings.menuBarOrganizer(L10n.shared.language)
        let menu = NSMenu()
        menu.addItem(
            withTitle: hiddenSectionShown ? text.contextHideHidden : text.contextShowHidden,
            action: #selector(contextToggleHidden),
            keyEquivalent: "")
        if UserDefaults.standard.bool(
            forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled) {
            menu.addItem(
                withTitle: alwaysHiddenSectionShown
                    ? text.contextHideAlways
                    : text.contextShowAlways,
                action: #selector(contextToggleAlways),
                keyEquivalent: "")
        }
        menu.addItem(
            withTitle: text.secondaryBar,
            action: #selector(contextSecondary),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: text.contextSettings,
            action: #selector(contextSettings),
            keyEquivalent: "")
        menu.addItem(
            withTitle: text.contextDisable,
            action: #selector(contextDisable),
            keyEquivalent: "")
        for menuItem in menu.items { menuItem.target = self }
        item?.statusItem.menu = menu
        button.performClick(nil)
        DispatchQueue.main.async { item?.statusItem.menu = nil }
    }

    private func moveErrorMessage(_ error: MenuBarItemMoveError) -> String {
        let text = FeatureStrings.menuBarOrganizer(L10n.shared.language)
        switch error {
        case .permissionMissing: return text.errorPermission
        case .itemUnavailable: return text.errorUnavailable
        case .itemNotMovable: return text.errorNotMovable
        case .provisionalIdentity: return text.errorUnresolved
        case .menuOpen: return text.errorMenuOpen
        case .eventCreationFailed: return text.errorEvent
        case .verificationFailed: return text.errorVerification
        case .busy: return text.errorBusy
        }
    }

    @objc private func contextToggleHidden() { toggleHiddenSection() }
    @objc private func contextToggleAlways() { toggleAlwaysHiddenSection() }
    @objc private func contextSecondary() { showSecondaryBar() }
    @objc private func contextSettings() {
        SettingsRouter.shared.page = .menuBarOrganizer
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
    @objc private func contextDisable() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.menuBarOrganizerEnabled)
        syncWithPreferences()
    }
}
