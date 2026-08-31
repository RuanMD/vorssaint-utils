// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Combine

/// Guards only Command-Q and Command-W. The tap deliberately passes every
/// unrelated event without consulting the main app or Accessibility APIs.
final class QuitProtectionService: ObservableObject {
    static let shared = QuitProtectionService()

    @Published private(set) var isRunning = false
    @Published private(set) var revision = 0

    private struct Pending {
        let shortcut: QuitProtectionShortcut
        let event: CGEvent
        let mode: QuitProtectionMode
        var triggered = false
    }

    private static let syntheticMarker: Int64 = 0x5652535341494E54
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?
    private var holdTimer: Timer?
    private var pendingExpiry: DispatchWorkItem?
    private var pending: Pending?
    private var swallowKeyUpFor: QuitProtectionShortcut?
    private var frontmostBundleIdentifier: String?
    private let hud = QuitProtectionHUD()

    private init() {}

    func syncWithPreferences() {
        let enabled = AppFeature.quitWindowProtection.isAvailable
            && (configuration(for: .quit).enabled || configuration(for: .close).enabled)
        guard enabled, Permissions.shared.accessibility else {
            stop()
            return
        }
        start()
    }

    var isEnabledForAnyShortcut: Bool {
        configuration(for: .quit).enabled || configuration(for: .close).enabled
    }

    func exceptions(for shortcut: QuitProtectionShortcut) -> [String] {
        (UserDefaults.standard.array(forKey: exceptionsKey(for: shortcut)) as? [String] ?? [])
            .filter { !$0.isEmpty }
            .sorted()
    }

    func addException(_ bundleIdentifier: String, for shortcut: QuitProtectionShortcut) {
        var values = exceptions(for: shortcut)
        guard !bundleIdentifier.isEmpty, !values.contains(bundleIdentifier) else { return }
        values.append(bundleIdentifier)
        UserDefaults.standard.set(values.sorted(), forKey: exceptionsKey(for: shortcut))
        revision += 1
        syncWithPreferences()
    }

    func removeException(_ bundleIdentifier: String, for shortcut: QuitProtectionShortcut) {
        let values = exceptions(for: shortcut).filter { $0 != bundleIdentifier }
        UserDefaults.standard.set(values, forKey: exceptionsKey(for: shortcut))
        revision += 1
        syncWithPreferences()
    }

    // MARK: Lifecycle

    private func start() {
        guard !isRunning else { return }
        guard installTap() else { return }
        isRunning = true
        frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.frontmostBundleIdentifier = (note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
        }
    }

    private func stop() {
        holdTimer?.invalidate()
        holdTimer = nil
        pendingExpiry?.cancel()
        pendingExpiry = nil
        pending = nil
        swallowKeyUpFor = nil
        hud.hide()

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil

        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isRunning = false
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<QuitProtectionService>
                    .fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: Event routing

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            cancelPending()
            return Unmanaged.passUnretained(event)
        }
        guard isRunning, !isSynthetic(event) else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown: return handleKeyDown(event)
        case .keyUp: return handleKeyUp(event)
        case .flagsChanged:
            handleFlagsChanged(event)
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 53, pending != nil {
            cancelPending()
            return nil
        }

        let shortcut = matchingShortcut(for: event)
        if let pending, shortcut != pending.shortcut {
            cancelPending()
        }

        guard let shortcut else { return Unmanaged.passUnretained(event) }
        let configuration = configuration(for: shortcut)
        guard configuration.enabled,
              QuitProtectionSupport.scopeAllows(configuration.scope,
                                                 bundleIdentifier: frontmostBundleIdentifier,
                                                 exceptions: configuration.exceptions)
        else { return Unmanaged.passUnretained(event) }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat {
            return pending?.shortcut == shortcut ? nil : Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let command = flags.contains(.maskCommand)
        let control = flags.contains(.maskControl)
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        let character = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased()

        switch configuration.mode {
        case .hold, .doublePress:
            guard QuitProtectionSupport.isBaseShortcut(
                keyCharacter: character,
                keyCode: keyCode,
                command: command,
                control: control,
                option: option,
                shift: shift,
                shortcut: shortcut
            ) else { return Unmanaged.passUnretained(event) }
            return handleConfirmationPress(shortcut: shortcut,
                                           mode: configuration.mode,
                                           event: event,
                                           configuration: configuration)

        case .extraModifier:
            if QuitProtectionSupport.isExtraShortcut(
                keyCharacter: character,
                keyCode: keyCode,
                command: command,
                control: control,
                option: option,
                shift: shift,
                shortcut: shortcut,
                extraModifier: configuration.extraModifier
            ) {
                swallowKeyUpFor = shortcut
                postSyntheticPress(from: event, removing: configuration.extraModifier)
                hideHUD()
                return nil
            }
            guard QuitProtectionSupport.isBaseShortcut(
                keyCharacter: character,
                keyCode: keyCode,
                command: command,
                control: control,
                option: option,
                shift: shift,
                shortcut: shortcut
            ) else { return Unmanaged.passUnretained(event) }
            beginPending(shortcut: shortcut, mode: .extraModifier, event: event)
            showHUD(for: shortcut, configuration: configuration, extraModifierOnly: true)
            return nil
        }
    }

    private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let pending else {
            if let swallowKeyUpFor,
               matchingShortcut(for: event) == swallowKeyUpFor {
                self.swallowKeyUpFor = nil
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        guard matchingShortcut(for: event) == pending.shortcut else {
            return Unmanaged.passUnretained(event)
        }

        if pending.triggered {
            postSyntheticKeyUp(from: event)
        }
        if pending.mode == .doublePress {
            return nil
        }
        cancelPending()
        return nil
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        guard let pending, !pending.triggered else { return }
        let flags = event.flags
        let commandHeld = flags.contains(.maskCommand)
        if pending.mode == .hold && !commandHeld {
            cancelPending()
        } else if pending.mode == .extraModifier && !commandHeld {
            cancelPending()
        }
    }

    // MARK: Confirmation state

    private func handleConfirmationPress(shortcut: QuitProtectionShortcut,
                                         mode: QuitProtectionMode,
                                         event: CGEvent,
                                         configuration: QuitProtectionConfiguration) -> Unmanaged<CGEvent>? {
        if mode == .doublePress, pending?.shortcut == shortcut {
            postSyntheticPress(from: event)
            swallowKeyUpFor = shortcut
            cancelPending()
            hideHUD()
            return nil
        }

        beginPending(shortcut: shortcut, mode: mode, event: event)
        showHUD(for: shortcut, configuration: configuration, extraModifierOnly: false)
        return nil
    }

    private func beginPending(shortcut: QuitProtectionShortcut,
                              mode: QuitProtectionMode,
                              event: CGEvent) {
        holdTimer?.invalidate()
        holdTimer = nil
        pendingExpiry?.cancel()
        pendingExpiry = nil
        pending = Pending(shortcut: shortcut, event: event, mode: mode)

        let configuration = configuration(for: shortcut)
        switch mode {
        case .hold:
            holdTimer = Timer.scheduledTimer(withTimeInterval:
                QuitProtectionSupport.sanitizedHoldDuration(configuration.holdDurationMilliseconds) / 1_000,
                repeats: false
            ) { [weak self] _ in self?.completeHold() }
        case .doublePress:
            let expiry = DispatchWorkItem { [weak self] in
                guard let self, self.pending?.mode == .doublePress else { return }
                self.cancelPending()
            }
            pendingExpiry = expiry
            DispatchQueue.main.asyncAfter(deadline: .now()
                + QuitProtectionSupport.sanitizedDoublePressInterval(configuration.doublePressIntervalMilliseconds) / 1_000,
                                           execute: expiry)
        case .extraModifier:
            let expiry = DispatchWorkItem { [weak self] in
                guard let self, self.pending?.mode == .extraModifier else { return }
                self.cancelPending()
            }
            pendingExpiry = expiry
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: expiry)
        }
    }

    private func completeHold() {
        guard var pending, pending.mode == .hold else { return }
        pending.triggered = true
        self.pending = pending
        postSyntheticKeyDown(from: pending.event)
        showReleaseHUD(for: pending.shortcut)
    }

    private func cancelPending() {
        holdTimer?.invalidate()
        holdTimer = nil
        pendingExpiry?.cancel()
        pendingExpiry = nil
        pending = nil
        hideHUD()
    }

    // MARK: Preferences and presentation

    private func configuration(for shortcut: QuitProtectionShortcut) -> QuitProtectionConfiguration {
        let defaults = UserDefaults.standard
        let enabledKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitEnabled : DefaultsKey.quitProtectionCloseEnabled
        let modeKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitMode : DefaultsKey.quitProtectionCloseMode
        let holdKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitHoldDurationMs : DefaultsKey.quitProtectionCloseHoldDurationMs
        let doubleKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitDoubleIntervalMs : DefaultsKey.quitProtectionCloseDoubleIntervalMs
        let modifierKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitExtraModifier : DefaultsKey.quitProtectionCloseExtraModifier
        let scopeKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitScope : DefaultsKey.quitProtectionCloseScope
        let feedbackKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitShowFeedback : DefaultsKey.quitProtectionCloseShowFeedback
        return QuitProtectionConfiguration(
            enabled: defaults.bool(forKey: enabledKey),
            mode: QuitProtectionSupport.modeFor(defaults.string(forKey: modeKey)),
            holdDurationMilliseconds: QuitProtectionSupport.sanitizedHoldDuration(defaults.double(forKey: holdKey)),
            doublePressIntervalMilliseconds: QuitProtectionSupport.sanitizedDoublePressInterval(defaults.double(forKey: doubleKey)),
            extraModifier: QuitProtectionSupport.extraModifierFor(defaults.string(forKey: modifierKey)),
            scope: QuitProtectionSupport.scopeFor(defaults.string(forKey: scopeKey)),
            exceptions: exceptions(for: shortcut),
            showFeedback: defaults.bool(forKey: feedbackKey)
        )
    }

    private func exceptionsKey(for shortcut: QuitProtectionShortcut) -> String {
        shortcut == .quit ? DefaultsKey.quitProtectionQuitExceptions : DefaultsKey.quitProtectionCloseExceptions
    }

    private func showHUD(for shortcut: QuitProtectionShortcut,
                         configuration: QuitProtectionConfiguration,
                         extraModifierOnly: Bool) {
        guard configuration.showFeedback else { return }
        let strings = FeatureStrings.quitProtection(L10n.shared.language)
        let title: String
        if extraModifierOnly {
            title = String(format: strings.extraHUDFormat,
                           "\(modifierSymbol(configuration.extraModifier))\(shortcut.symbol)")
        } else if configuration.mode == .hold {
            title = String(format: strings.holdHUDFormat, shortcut.symbol)
        } else {
            title = String(format: strings.doubleHUDFormat, shortcut.symbol)
        }
        hud.show(title: title, detail: strings.cancelHint)
    }

    private func showReleaseHUD(for shortcut: QuitProtectionShortcut) {
        let configuration = configuration(for: shortcut)
        guard configuration.showFeedback else { return }
        let strings = FeatureStrings.quitProtection(L10n.shared.language)
        hud.show(title: strings.releaseHint, detail: shortcut.symbol)
    }

    private func hideHUD() { hud.hide() }

    private func modifierSymbol(_ modifier: QuitProtectionExtraModifier) -> String {
        switch modifier {
        case .shift: return "⇧"
        case .option: return "⌥"
        case .control: return "⌃"
        }
    }

    // MARK: Event helpers

    private func matchingShortcut(for event: CGEvent) -> QuitProtectionShortcut? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let character = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased()
        return QuitProtectionShortcut.allCases.first {
            QuitProtectionSupport.matchesKey(keyCharacter: character,
                                             keyCode: keyCode,
                                             shortcut: $0)
        }
    }

    private func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker
    }

    private func postSyntheticKeyDown(from event: CGEvent,
                                      removing modifier: QuitProtectionExtraModifier? = nil) {
        let copy = event.copy()!
        if let modifier { copy.flags = flags(for: event, removing: modifier) }
        copy.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        copy.post(tap: .cghidEventTap)
    }

    private func postSyntheticKeyUp(from event: CGEvent,
                                    removing modifier: QuitProtectionExtraModifier? = nil) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let copy = CGEvent(keyboardEventSource: nil,
                                 virtualKey: CGKeyCode(keyCode),
                                 keyDown: false) else { return }
        copy.flags = modifier.map { flags(for: event, removing: $0) } ?? event.flags
        copy.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        copy.post(tap: .cghidEventTap)
    }

    private func postSyntheticPress(from event: CGEvent,
                                    removing modifier: QuitProtectionExtraModifier? = nil) {
        postSyntheticKeyDown(from: event, removing: modifier)
        postSyntheticKeyUp(from: event, removing: modifier)
    }

    private func flags(for event: CGEvent,
                       removing modifier: QuitProtectionExtraModifier) -> CGEventFlags {
        var flags = event.flags
        switch modifier {
        case .shift: flags.remove(.maskShift)
        case .option: flags.remove(.maskAlternate)
        case .control: flags.remove(.maskControl)
        }
        return flags
    }
}
