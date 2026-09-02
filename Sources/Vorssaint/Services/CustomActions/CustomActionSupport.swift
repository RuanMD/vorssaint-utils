// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

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
    case inputTooLarge
    case timeout
    case cancelled
    case process(String)
    case clipboardFailed

    var errorDescription: String? {
        let strings = FeatureStrings.customActions(L10n.shared.language)
        switch self {
        case .emptyScript: return strings.emptyScript
        case .scriptTooLarge: return strings.scriptTooLarge
        case .forbiddenAPI(let name): return strings.forbiddenAPI(name)
        case .javascript(let message): return "\(strings.javascriptError): \(message)"
        case .nonTextResult: return strings.nonTextResult
        case .resultTooLarge: return strings.resultTooLarge
        case .inputTooLarge: return strings.inputTooLarge
        case .timeout: return strings.timeout
        case .cancelled: return strings.cancelled
        case .process(let message): return "\(strings.processError): \(message)"
        case .clipboardFailed: return strings.clipboardFailed
        }
    }
}

enum CustomActionSupport {
    static let maxScriptLength = 64 * 1024
    static let maxResultLength = 1_000_000
    static let maxInputLength = 1_000_000
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

    static func makePayload(script: String, context: CustomActionContext,
                            input: CustomActionInput) -> Data? {
        let payload: [String: String] = [
            "selectedText": context.selectedText,
            "clipboardText": context.clipboardText,
            "input": resolveInput(context: context, source: input)
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    static func execute(script: String, context: CustomActionContext, input: CustomActionInput) -> Result<String, CustomActionRuntimeError> {
        if let error = validate(script: script) { return .failure(error) }
        return CustomActionJavaScriptExecutor.run(script: script, context: context, input: input)
    }
}

private enum CustomActionJXAResult: Decodable {
    case success(String)
    case failure(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(Bool.self, forKey: .ok) {
            self = .success(try container.decode(String.self, forKey: .value))
        } else {
            self = .failure(try container.decode(String.self, forKey: .error))
        }
    }

    private enum CodingKeys: String, CodingKey { case ok, value, error }
}

enum CustomActionJavaScriptExecutor {
    static let timeout: TimeInterval = 2

    static func run(script: String, context: CustomActionContext,
                    input: CustomActionInput,
                    isCancelled: (() -> Bool)? = nil) -> Result<String, CustomActionRuntimeError> {
        if let validationError = CustomActionSupport.validate(script: script) { return .failure(validationError) }
        guard let payload = CustomActionSupport.makePayload(script: script, context: context, input: input),
              payload.count <= CustomActionSupport.maxInputLength else { return .failure(.inputTooLarge) }

            // The user script is nested in a function whose dangerous JXA globals
            // are shadowed. The only values passed into it are the three strings.
            let wrapper = """
            ObjC.import('Foundation');
            var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
            var payload = JSON.parse(ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)));
            function invoke(selectedText, clipboardText, input, Application, ObjC, $, FileManager, NSProcessInfo, NSURLSession, XMLHttpRequest, process, require) {
              'use strict';
              try {
                var value = (function() {
            \(script)
                })();
                if (typeof value !== 'string') return JSON.stringify({ok:false,error:'non-text result'});
                return JSON.stringify({ok:true,value:value});
              } catch (error) { return JSON.stringify({ok:false,error:String(error)}); }
            }
            invoke(payload.selectedText, payload.clipboardText, payload.input, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined);
            """
            let processResult = BoundedProcessRunner.run(
                "/usr/bin/osascript", ["-l", "JavaScript", "-e", wrapper],
                timeout: timeout, maxOutputBytes: CustomActionSupport.maxResultLength,
                input: payload, isCancelled: isCancelled)
            if processResult.cancelled { return .failure(.cancelled) }
            if processResult.timedOut { return .failure(.timeout) }
            if processResult.outputExceeded { return .failure(.resultTooLarge) }
            guard processResult.status == 0 else {
                return .failure(.process("exit \(processResult.status)"))
            }
            guard let result = try? JSONDecoder().decode(CustomActionJXAResult.self, from: processResult.output) else {
                return .failure(.process("invalid output"))
            }
        switch result {
            case .success(let value):
                guard value.utf8.count <= CustomActionSupport.maxResultLength else { return .failure(.resultTooLarge) }
                return .success(value)
            case .failure(let message): return .failure(message == "non-text result" ? .nonTextResult : .javascript(message))
            }
        }
    }
