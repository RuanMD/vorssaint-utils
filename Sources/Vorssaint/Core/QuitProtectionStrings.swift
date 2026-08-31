// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct QuitProtectionStrings {
    let name: String
    let description: String
    let intro: String
    let enabled: String
    let enabledCaption: String
    let mode: String
    let hold: String
    let doublePress: String
    let extraModifier: String
    let holdDuration: String
    let doublePressInterval: String
    let modifier: String
    let appScope: String
    let allApps: String
    let selectedOnly: String
    let allExceptSelected: String
    let exceptions: String
    let noExceptions: String
    let addApp: String
    let feedback: String
    let accessibilityCaption: String
    let holdHUDFormat: String
    let doubleHUDFormat: String
    let extraHUDFormat: String
    let cancelHint: String
    let releaseHint: String

    static func make(_ language: AppLanguage) -> QuitProtectionStrings {
        language == .ptBR ? ptBR : enUS
    }

    static let ptBR = QuitProtectionStrings(
        name: "Proteção de encerramento",
        description: "Protege ⌘Q e ⌘W contra toques acidentais",
        intro: "Configure cada atalho separadamente. A ação original só passa depois da confirmação escolhida.",
        enabled: "Proteger este atalho",
        enabledCaption: "Outros atalhos com Command continuam funcionando normalmente.",
        mode: "Modo de confirmação",
        hold: "Segurar para confirmar",
        doublePress: "Pressionar duas vezes",
        extraModifier: "Exigir modificador extra",
        holdDuration: "Tempo pressionado",
        doublePressInterval: "Intervalo entre pressões",
        modifier: "Modificador extra",
        appScope: "Aplicativos",
        allApps: "Todos os aplicativos",
        selectedOnly: "Somente aplicativos selecionados",
        allExceptSelected: "Todos, exceto os selecionados",
        exceptions: "Exceções",
        noExceptions: "Nenhum aplicativo selecionado",
        addApp: "Adicionar aplicativo…",
        feedback: "Mostrar feedback visual",
        accessibilityCaption: "A proteção usa Acessibilidade para observar apenas ⌘Q e ⌘W globalmente.",
        holdHUDFormat: "Segure %@ para encerrar/fechar",
        doubleHUDFormat: "Pressione %@ novamente para encerrar/fechar",
        extraHUDFormat: "Use %@ para encerrar/fechar",
        cancelHint: "Esc cancela",
        releaseHint: "Solte para confirmar"
    )

    static let enUS = QuitProtectionStrings(
        name: "Quit & close protection",
        description: "Protects ⌘Q and ⌘W from accidental presses",
        intro: "Configure each shortcut independently. The original action passes only after the selected confirmation.",
        enabled: "Protect this shortcut",
        enabledCaption: "Other Command shortcuts continue to work normally.",
        mode: "Confirmation mode",
        hold: "Hold to confirm",
        doublePress: "Double press",
        extraModifier: "Require extra modifier",
        holdDuration: "Hold duration",
        doublePressInterval: "Double press interval",
        modifier: "Extra modifier",
        appScope: "Applications",
        allApps: "All applications",
        selectedOnly: "Selected applications only",
        allExceptSelected: "All except selected applications",
        exceptions: "Exceptions",
        noExceptions: "No applications selected",
        addApp: "Add application…",
        feedback: "Show visual feedback",
        accessibilityCaption: "Protection uses Accessibility to observe only ⌘Q and ⌘W globally.",
        holdHUDFormat: "Hold %@ to quit/close",
        doubleHUDFormat: "Press %@ again to quit/close",
        extraHUDFormat: "Use %@ to quit/close",
        cancelHint: "Esc cancels",
        releaseHint: "Release to confirm"
    )
}

extension FeatureStrings {
    static func quitProtection(_ language: AppLanguage) -> QuitProtectionStrings {
        QuitProtectionStrings.make(language)
    }
}
