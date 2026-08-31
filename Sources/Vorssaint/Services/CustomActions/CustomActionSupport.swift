// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import JavaScriptCore

enum CustomActionInput: String, Codable, CaseIterable, Identifiable {
    case selectedText
    case clipboardText
    case automatic

    var id: String { rawValue }
}

enum CustomActionOutput: String, Codable, CaseIterable, Identifiable {
    case replaceSelection
    case insertAtCursor
    case copyToClipboard
    case preview

    var id: String { rawValue }
}

struct CustomAction: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var script: String
    var input: CustomActionInput
    var output: CustomActionOutput
    var shortcut: String
    var showInRadialMenu: Bool
    var showInCommandBar: Bool
    var enabled: Bool

    init(id: UUID = UUID(), name: String = "", description: String = "",
         script: String = "", input: CustomActionInput = .automatic,
         output: CustomActionOutput = .preview, shortcut: String = "",
         showInRadialMenu: Bool = false, showInCommandBar: Bool = true,
         enabled: Bool = true) {
        self.id = id
        self.name = name
        self.description = description
        self.script = script
        self.input = input
        self.output = output
        self.shortcut = shortcut
        self.showInRadialMenu = showInRadialMenu
        self.showInCommandBar = showInCommandBar
        self.enabled = enabled
    }
}

struct CustomActionContext: Equatable {
    let selectedText: String
    let clipboardText: String

    func input(for source: CustomActionInput) -> String {
        switch source {
        case .selectedText: return selectedText
        case .clipboardText: return clipboardText
        case .automatic: return selectedText.isEmpty ? clipboardText : selectedText
        }
    }
}

enum CustomActionRuntimeError: LocalizedError, Equatable {
    case emptyScript
    case scriptTooLarge
    case forbiddenAPI(String)
    case javascript(String)
    case nonTextResult
    case resultTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyScript: return "O script JavaScript está vazio."
        case .scriptTooLarge: return "O script excede o limite permitido."
        case .forbiddenAPI(let name): return "A API '\(name)' não está disponível em Custom Actions."
        case .javascript(let message): return message
        case .nonTextResult: return "O script precisa retornar um texto."
        case .resultTooLarge: return "O resultado excede o limite permitido."
        }
    }
}

enum CustomActionSupport {
    static let maxScriptLength = 64 * 1024
    static let maxResultLength = 1_000_000
    static let maxStoredActions = 100

    static func sanitized(_ action: CustomAction) -> CustomAction? {
        let name = String(action.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let description = String(action.description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        guard !name.isEmpty, !action.script.isEmpty, action.script.utf8.count <= maxScriptLength else { return nil }
        guard GlobalShortcut(storageValue: action.shortcut) != nil || action.shortcut.isEmpty else { return nil }
        var copy = action
        copy.name = name
        copy.description = description
        return copy
    }

    static func decode(_ data: Data?) -> [CustomAction] {
        guard let data, let actions = try? JSONDecoder().decode([CustomAction].self, from: data) else { return [] }
        var ids = Set<UUID>()
        return actions.compactMap { action in
            guard ids.insert(action.id).inserted else { return nil }
            return sanitized(action)
        }.prefix(maxStoredActions).map { $0 }
    }

    static func encode(_ actions: [CustomAction]) -> Data? {
        try? JSONEncoder().encode(Array(actions.compactMap(sanitized).prefix(maxStoredActions)))
    }

    static func validate(script: String) -> CustomActionRuntimeError? {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .emptyScript }
        guard script.utf8.count <= maxScriptLength else { return .scriptTooLarge }
        let forbidden = ["FileManager", "NSProcessInfo", "NSURLSession", "XMLHttpRequest", "process", "require", "importScripts", "eval", "Function"]
        if let token = forbidden.first(where: { script.contains($0) }) { return .forbiddenAPI(token) }
        return nil
    }

    static func resolveInput(context: CustomActionContext, source: CustomActionInput) -> String {
        context.input(for: source)
    }

    static func execute(script: String, context: CustomActionContext, input: CustomActionInput) -> Result<String, CustomActionRuntimeError> {
        if let error = validate(script: script) { return .failure(error) }
        let selected = JSContext()!
        var exception: String?
        selected.exceptionHandler = { _, value in exception = value?.toString() }
        selected.setObject(context.selectedText, forKeyedSubscript: "selectedText" as NSString)
        selected.setObject(context.clipboardText, forKeyedSubscript: "clipboardText" as NSString)
        selected.setObject(resolveInput(context: context, source: input), forKeyedSubscript: "input" as NSString)
        let value = selected.evaluateScript("(function() {\n\(script)\n})()")
        if let exception { return .failure(.javascript(exception)) }
        guard let value, !value.isNull, !value.isUndefined, let output = value.toString() else {
            return .failure(.nonTextResult)
        }
        guard output.utf8.count <= maxResultLength else { return .failure(.resultTooLarge) }
        return .success(output)
    }
}
