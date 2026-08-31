// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct CustomActionsSettings: View {
    @ObservedObject private var service = CustomActionService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var selectedID: CustomAction.ID?
    @State private var draft = CustomAction()
    @State private var testInput = ""

    private var strings: CustomActionsFeatureStrings {
        FeatureStrings.customActions(l10n.language)
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(service.actions) { action in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.name).font(.headline)
                        Text(action.description.isEmpty ? action.input.rawValue : action.description)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .tag(action.id)
                    .contextMenu {
                        Button(strings.duplicateButton) { select(service.duplicate(action)) }
                        Button(strings.deleteButton, role: .destructive) { service.remove(action) }
                    }
                }
            }
            .frame(minWidth: 220, idealWidth: 240)

            Divider()

            Form {
                Section(strings.actionSection) {
                    TextField(strings.name, text: $draft.name)
                    TextField(strings.description, text: $draft.description)
                    Toggle(strings.enabled, isOn: $draft.enabled)
                }

                Section(strings.javascriptSection) {
                    TextEditor(text: $draft.script)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    Text(strings.availableVariables)
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section(strings.inputOutputSection) {
                    Picker(strings.input, selection: $draft.input) {
                        Text(strings.selectedText).tag(CustomActionInput.selectedText)
                        Text(strings.clipboardText).tag(CustomActionInput.clipboardText)
                        Text(strings.automatic).tag(CustomActionInput.automatic)
                    }
                    Picker(strings.output, selection: $draft.output) {
                        Text(strings.replaceSelection).tag(CustomActionOutput.replaceSelection)
                        Text(strings.insertAtCursor).tag(CustomActionOutput.insertAtCursor)
                        Text(strings.copyToClipboard).tag(CustomActionOutput.copyToClipboard)
                        Text(strings.preview).tag(CustomActionOutput.preview)
                    }
                    Toggle(strings.showCommandBar, isOn: $draft.showInCommandBar)
                    Toggle(strings.showRadialMenu, isOn: $draft.showInRadialMenu)
                }

                Section(strings.testInputSection) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $testInput)
                            .frame(minHeight: 76, maxHeight: 130)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                        if testInput.isEmpty {
                            Text(strings.testInputPlaceholder)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    Text(strings.testInputHint)
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(strings.testButton) {
                            service.execute(draft, context: CustomActionContext(
                                selectedText: testInput,
                                clipboardText: testInput), applyOutput: false)
                        }
                        Button(strings.saveButton) {
                            guard service.save(draft) else { return }
                            selectedID = draft.id
                        }
                        Button(strings.newButton) { draft = CustomAction(); selectedID = nil; testInput = "" }
                    }
                    if let error = service.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    if let preview = service.lastPreview {
                        Text(preview).textSelection(.enabled)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Text(strings.testOnlyHint)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .navigationTitle(strings.pageTitle)
        .onAppear { service.syncWithPreferences(); select(service.actions.first) }
        .onChange(of: selectedID) { _, id in
            guard let id, let action = service.actions.first(where: { $0.id == id }) else { return }
            draft = action
        }
    }

    private func select(_ action: CustomAction?) {
        guard let action else { return }
        draft = action
        selectedID = action.id
    }
}
