// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

@MainActor
final class MenuBarOrganizerHotkeyService {
    private static let signature: OSType = 0x564D_4241 // VMBA

    private var eventHandler: EventHandlerRef?
    private var registered: [GlobalShortcutRole: EventHotKeyRef] = [:]
    private var actions: [GlobalShortcutRole: () -> Void] = [:]

    func sync(actions: [GlobalShortcutRole: () -> Void]) {
        stop()
        self.actions = actions
        guard AppFeature.menuBarOrganizer.isAvailable,
              AppFeature.menuBarOrganizer.isSupportedOnCurrentSystem,
              UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerEnabled)
        else { return }

        installEventHandlerIfNeeded()
        let roles: [GlobalShortcutRole] = [
            .menuBarShowHidden, .menuBarShowAll, .menuBarHideAll,
            .menuBarSearch, .menuBarSecondaryBar,
        ]
        for role in roles where role.requiredEnableKeys.allSatisfy({ UserDefaults.standard.bool(forKey: $0) }) {
            guard GlobalShortcutRole.conflict(for: role.savedShortcut,
                                               excluding: role) == nil
            else { continue }
            register(role)
        }
    }

    func stop() {
        for ref in registered.values { UnregisterEventHotKey(ref) }
        registered.removeAll()
        actions.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard hotKeyID.signature == MenuBarOrganizerHotkeyService.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let service = Unmanaged<MenuBarOrganizerHotkeyService>
                .fromOpaque(userData).takeUnretainedValue()
            let roles: [GlobalShortcutRole] = [
                .menuBarShowHidden, .menuBarShowAll, .menuBarHideAll,
                .menuBarSearch, .menuBarSecondaryBar,
            ]
            guard hotKeyID.id > 0, Int(hotKeyID.id) <= roles.count else {
                return OSStatus(eventNotHandledErr)
            }
            let role = roles[Int(hotKeyID.id) - 1]
            DispatchQueue.main.async { [weak service] in service?.invoke(role) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    private func invoke(_ role: GlobalShortcutRole) {
        actions[role]?()
    }

    private func register(_ role: GlobalShortcutRole) {
        let roles: [GlobalShortcutRole] = [
            .menuBarShowHidden, .menuBarShowAll, .menuBarHideAll,
            .menuBarSearch, .menuBarSecondaryBar,
        ]
        guard let index = roles.firstIndex(of: role) else { return }
        let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(role.savedShortcut.carbonKeyCode,
                                         role.savedShortcut.carbonModifiers,
                                         id, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref { registered[role] = ref }
    }
}
