// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized chrome for the Custom Actions editor. The action name, description
/// and script remain user-authored data and are intentionally not translated.
struct CustomActionsFeatureStrings {
    let pageTitle: String
    let actionSection: String
    let nameColumn: String
    let statusColumn: String
    let activeStatus: String
    let inactiveStatus: String
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
    let emptyScript: String
    let scriptTooLarge: String
    let nonTextResult: String
    let resultTooLarge: String
    let inputTooLarge: String
    let timeout: String
    let cancelled: String
    let processError: String
    let javascriptError: String
    let forbiddenAPI: (String) -> String
    let noSelection: String
    let pasteFailed: String
    let clipboardFailed: String
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
        nameColumn: "Name",
        statusColumn: "Status",
        activeStatus: "Enabled",
        inactiveStatus: "Disabled",
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
        testOnlyHint: "Preview only — use Command Bar, shortcut or Radial Menu to apply",
        emptyScript: "The JavaScript is empty.", scriptTooLarge: "The script is too large.",
        nonTextResult: "The script must return text.", resultTooLarge: "The result is too large.",
        inputTooLarge: "The input is too large.", timeout: "The action timed out.",
        cancelled: "The action was cancelled.", processError: "The action process failed.",
        javascriptError: "JavaScript error", forbiddenAPI: { "The API '\($0)' is unavailable in Custom Actions." },
        noSelection: "There is no selected text to replace.", pasteFailed: "Could not deliver the result to the current field.", clipboardFailed: "Could not copy the result to the clipboard."
    )

    static let ptBR = CustomActionsFeatureStrings(
        pageTitle: "Ações personalizadas",
        actionSection: "Ação personalizada",
        nameColumn: "Nome",
        statusColumn: "Estado",
        activeStatus: "Ativada",
        inactiveStatus: "Desativada",
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
        testOnlyHint: "Somente prévia — use a Barra de comandos, o atalho ou o Menu radial para aplicar",
        emptyScript: "O JavaScript está vazio.", scriptTooLarge: "O script é grande demais.",
        nonTextResult: "O script precisa retornar texto.", resultTooLarge: "O resultado é grande demais.",
        inputTooLarge: "A entrada é grande demais.", timeout: "A ação excedeu o tempo limite.",
        cancelled: "A ação foi cancelada.", processError: "O processo da ação falhou.",
        javascriptError: "Erro de JavaScript", forbiddenAPI: { "A API '\($0)' não está disponível em Ações personalizadas." },
        noSelection: "Não existe texto selecionado para substituir.", pasteFailed: "Não foi possível entregar o resultado ao campo atual.", clipboardFailed: "Não foi possível copiar o resultado para o clipboard."
    )
}
