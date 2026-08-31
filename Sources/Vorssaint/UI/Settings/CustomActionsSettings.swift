// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct CustomActionsSettings: View {
    @ObservedObject private var service = CustomActionService.shared
    @State private var selectedID: CustomAction.ID?
    @State private var draft = CustomAction()

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
                        Button("Duplicate") { select(service.duplicate(action)) }
                        Button("Delete", role: .destructive) { service.remove(action) }
                    }
                }
            }
            .frame(minWidth: 220, idealWidth: 240)

            Divider()

            Form {
                Section("Custom Action") {
                    TextField("Name", text: $draft.name)
                    TextField("Description", text: $draft.description)
                    Toggle("Enabled", isOn: $draft.enabled)
                }

                Section("JavaScript") {
                    TextEditor(text: $draft.script)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    Text("Available: selectedText, clipboardText, input")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Input and Output") {
                    Picker("Input", selection: $draft.input) {
                        Text("Selected text").tag(CustomActionInput.selectedText)
                        Text("Clipboard").tag(CustomActionInput.clipboardText)
                        Text("Automatic").tag(CustomActionInput.automatic)
                    }
                    Picker("Output", selection: $draft.output) {
                        Text("Replace selection").tag(CustomActionOutput.replaceSelection)
                        Text("Insert at cursor").tag(CustomActionOutput.insertAtCursor)
                        Text("Copy to clipboard").tag(CustomActionOutput.copyToClipboard)
                        Text("Preview").tag(CustomActionOutput.preview)
                    }
                    Toggle("Show in Command Bar", isOn: $draft.showInCommandBar)
                    Toggle("Show in Radial Menu", isOn: $draft.showInRadialMenu)
                }

                Section {
                    HStack {
                        Button("Test") {
                            service.execute(draft, context: CustomActionContext(
                                selectedText: "Selected sample",
                                clipboardText: "Clipboard sample"), applyOutput: false)
                        }
                        Button("Save") {
                            guard service.save(draft) else { return }
                            selectedID = draft.id
                        }
                        Button("New") { draft = CustomAction(); selectedID = nil }
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
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .navigationTitle("Custom Actions")
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
