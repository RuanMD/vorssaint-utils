// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized chrome for the Custom Actions editor. The action name, description
/// and script remain user-authored data and are intentionally not translated.
struct CustomActionsFeatureStrings {
    let pageTitle: String
    let actionSection: String
    let name: String
    let description: String
    let enabled: String
    let javascriptSection: String
    let availableVariables: String
    let inputOutputSection: String
    let input: String
    let selectedText: String
    let clipboardText: String
    let automatic: String
    let output: String
    let replaceSelection: String
    let insertAtCursor: String
    let copyToClipboard: String
    let preview: String
    let showCommandBar: String
    let showRadialMenu: String
    let testInputSection: String
    let testInputPlaceholder: String
    let testInputHint: String
    let testButton: String
    let saveButton: String
    let newButton: String
    let duplicateButton: String
    let deleteButton: String
    let testOnlyHint: String
}

extension FeatureStrings {
    static func customActions(_ language: AppLanguage) -> CustomActionsFeatureStrings {
        switch language {
        case .ptBR: return .ptBR
        default: return .enUS
        }
    }
}

extension CustomActionsFeatureStrings {
    static let enUS = CustomActionsFeatureStrings(
        pageTitle: "Custom Actions",
        actionSection: "Custom Action",
        name: "Name",
        description: "Description",
        enabled: "Enabled",
        javascriptSection: "JavaScript",
        availableVariables: "Available: selectedText, clipboardText, input",
        inputOutputSection: "Input and Output",
        input: "Input",
        selectedText: "Selected text",
        clipboardText: "Clipboard",
        automatic: "Automatic",
        output: "Output",
        replaceSelection: "Replace selection",
        insertAtCursor: "Insert at cursor",
        copyToClipboard: "Copy to clipboard",
        preview: "Preview",
        showCommandBar: "Show in Command Bar",
        showRadialMenu: "Show in Radial Menu",
        testInputSection: "Test input",
        testInputPlaceholder: "Type or paste text to test this action",
        testInputHint: "Testing uses this text only. It does not change the selected text or clipboard.",
        testButton: "Test",
        saveButton: "Save",
        newButton: "New",
        duplicateButton: "Duplicate",
        deleteButton: "Delete",
        testOnlyHint: "Preview only — use Command Bar, shortcut or Radial Menu to apply"
    )

    static let ptBR = CustomActionsFeatureStrings(
        pageTitle: "Ações personalizadas",
        actionSection: "Ação personalizada",
        name: "Nome",
        description: "Descrição",
        enabled: "Ativada",
        javascriptSection: "JavaScript",
        availableVariables: "Disponíveis: selectedText, clipboardText, input",
        inputOutputSection: "Entrada e saída",
        input: "Entrada",
        selectedText: "Texto selecionado",
        clipboardText: "Clipboard",
        automatic: "Automático",
        output: "Saída",
        replaceSelection: "Substituir seleção",
        insertAtCursor: "Inserir no cursor",
        copyToClipboard: "Copiar para o clipboard",
        preview: "Pré-visualização",
        showCommandBar: "Mostrar na Barra de comandos",
        showRadialMenu: "Mostrar no Menu radial",
        testInputSection: "Texto para testar",
        testInputPlaceholder: "Digite ou cole um texto para testar esta ação",
        testInputHint: "O teste usa somente este texto. Ele não altera o texto selecionado nem o clipboard.",
        testButton: "Testar",
        saveButton: "Salvar",
        newButton: "Novo",
        duplicateButton: "Duplicar",
        deleteButton: "Excluir",
        testOnlyHint: "Somente prévia — use a Barra de comandos, o atalho ou o Menu radial para aplicar"
    )
}
