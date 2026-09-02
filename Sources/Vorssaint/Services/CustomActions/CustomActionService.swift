// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

private final class CustomActionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.withLock { value = true } }
    var isCancelled: Bool { lock.withLock { value } }
}

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
    private var activeCancellation: CustomActionCancellation?
    private init() {}

    func syncWithPreferences() {
        actions = CustomActionSupport.decode(UserDefaults.standard.data(forKey: DefaultsKey.customActions))
        syncHotkeys()
    }

    func suspend() {
        generation &+= 1
        activeCancellation?.cancel()
        activeCancellation = nil
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
        activeCancellation?.cancel()
        let cancellation = CustomActionCancellation()
        activeCancellation = cancellation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = context ?? CustomActionContext(
                selectedText: CommandBarSelectionReader.readSelectedText(),
                clipboardText: NSPasteboard.general.string(forType: .string) ?? "")
            let result = CustomActionJavaScriptExecutor.run(script: action.script,
                                                             context: snapshot,
                                                             input: action.input,
                                                             isCancelled: { cancellation.isCancelled })
            DispatchQueue.main.async {
                guard let self, self.generation == runGeneration else { return }
                self.activeCancellation = nil
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
                            subtitle: action.description.isEmpty
                                ? FeatureStrings.customActions(L10n.shared.language).actionSection
                                : action.description,
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
            guard TransientPaste.shared.copy(text, didFail: { [weak self] in
                self?.lastError = CustomActionRuntimeError.clipboardFailed.localizedDescription
            }) else {
                lastError = CustomActionRuntimeError.clipboardFailed.localizedDescription
                return
            }
        case .insertAtCursor:
            paste(text)
        case .replaceSelection:
            guard !context.selectedText.isEmpty else {
                lastError = FeatureStrings.customActions(L10n.shared.language).noSelection
                return
            }
            paste(text)
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

    private func paste(_ text: String) {
        guard TransientPaste.shared.paste(text, didFail: { [weak self] in
            self?.lastError = FeatureStrings.customActions(L10n.shared.language).pasteFailed
        }) else {
            lastError = FeatureStrings.customActions(L10n.shared.language).pasteFailed
            return
        }
    }
}
