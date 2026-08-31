// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics

/// Coordinates user-defined text transformations. The JavaScript runtime is
/// deliberately kept behind this service: scripts receive a snapshot of
/// strings, while AppKit, pasteboard and Accessibility remain native-only.
final class CustomActionService: ObservableObject {
    static let shared = CustomActionService()

    @Published private(set) var actions: [CustomAction] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastPreview: String?

    private var generation = 0
    private var hotkeys: [QuickToolHotkey] = []
    private init() {}

    func syncWithPreferences() {
        actions = CustomActionSupport.decode(UserDefaults.standard.data(forKey: DefaultsKey.customActions))
        syncHotkeys()
    }

    func suspend() {
        generation &+= 1
        for hotkey in hotkeys { hotkey.unregister() }
        hotkeys = []
        lastPreview = nil
        lastError = nil
    }

    func save(_ action: CustomAction) -> Bool {
        guard let action = CustomActionSupport.sanitized(action) else { return false }
        var next = actions
        if let index = next.firstIndex(where: { $0.id == action.id }) {
            next[index] = action
        } else {
            next.append(action)
        }
        guard let data = CustomActionSupport.encode(next) else { return false }
        UserDefaults.standard.set(data, forKey: DefaultsKey.customActions)
        actions = CustomActionSupport.decode(data)
        syncHotkeys()
        return true
    }

    func setEnabled(_ action: CustomAction, enabled: Bool) {
        var updated = action
        updated.enabled = enabled
        _ = save(updated)
    }

    func remove(_ action: CustomAction) {
        let next = actions.filter { $0.id != action.id }
        UserDefaults.standard.set(CustomActionSupport.encode(next), forKey: DefaultsKey.customActions)
        actions = next
        syncHotkeys()
    }

    func duplicate(_ action: CustomAction) -> CustomAction? {
        var copy = action
        copy = CustomAction(id: UUID(), name: action.name + " Copy",
                            description: action.description, script: action.script,
                            input: action.input, output: action.output,
                            shortcut: "", showInRadialMenu: action.showInRadialMenu,
                            showInCommandBar: action.showInCommandBar, enabled: action.enabled)
        return save(copy) ? copy : nil
    }

    /// Runs an action using the context that existed at invocation time.
    /// Reading selection and pasteboard is off the main thread because either
    /// service can block behind another application.
    func execute(_ action: CustomAction, context: CustomActionContext? = nil,
                 applyOutput: Bool = true) {
        guard action.enabled else { return }
        generation &+= 1
        let runGeneration = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = context ?? CustomActionContext(
                selectedText: CommandBarSelectionReader.readSelectedText(),
                clipboardText: NSPasteboard.general.string(forType: .string) ?? "")
            let result = CustomActionSupport.execute(script: action.script,
                                                      context: snapshot,
                                                      input: action.input)
            DispatchQueue.main.async {
                guard let self, self.generation == runGeneration else { return }
                switch result {
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.lastPreview = nil
                case .success(let text):
                    self.lastError = nil
                    self.lastPreview = text
                    guard applyOutput else { return }
                    self.apply(text, output: action.output, context: snapshot)
                }
            }
        }
    }

    func commandBarEntries() -> [CommandBarEntry] {
        guard AppFeature.customActions.isAvailable else { return [] }
        return actions.filter { $0.enabled && $0.showInCommandBar }.map { action in
            CommandBarEntry(id: "custom-action.\(action.id.uuidString)",
                            stableKey: "custom-action.\(action.id.uuidString)",
                            title: action.name,
                            subtitle: action.description.isEmpty ? "Custom Action" : action.description,
                            keywords: "custom action javascript \(action.name)",
                            icon: .symbol("wand.and.stars"),
                            countsUsage: false) { [weak self] _ in
                self?.execute(action)
            }
        }
    }

    private func apply(_ text: String, output: CustomActionOutput, context: CustomActionContext) {
        switch output {
        case .preview:
            lastPreview = text
        case .copyToClipboard:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .insertAtCursor:
            writeAndPaste(text, replacingSelection: false)
        case .replaceSelection:
            guard !context.selectedText.isEmpty else {
                lastError = "Não existe texto selecionado para substituir."
                return
            }
            writeAndPaste(text, replacingSelection: true)
        }
    }

    private func syncHotkeys() {
        for hotkey in hotkeys { hotkey.unregister() }
        hotkeys = []
        var id: UInt32 = 500
        for action in actions where action.enabled && !action.shortcut.isEmpty {
            guard let shortcut = GlobalShortcut(storageValue: action.shortcut) else { continue }
            let hotkey = QuickToolHotkey(id: id)
            hotkey.onPress = { [weak self] in self?.execute(action) }
            _ = hotkey.sync(enabled: true, shortcut: shortcut)
            hotkeys.append(hotkey)
            id += 1
        }
    }

    private func writeAndPaste(_ text: String, replacingSelection _: Bool) {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            lastError = "Não foi possível escrever o resultado no clipboard."
            return
        }
        postPasteWhenModifiersAreReleased(attempt: 0)
    }

    private func postPasteWhenModifiersAreReleased(attempt: Int) {
        guard attempt < 100 else {
            lastError = "Não foi possível entregar o resultado ao campo atual."
            return
        }
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        guard held.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
                self?.postPasteWhenModifiersAreReleased(attempt: attempt + 1)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let down = CGEvent(keyboardEventSource: source,
                                     virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source,
                                   virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
