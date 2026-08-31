// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MenuBarOrganizerAdvancedStrings {
    let title: String
    let showHidden: String
    let showAll: String
    let hideAll: String
    let search: String
    let secondaryBar: String
    let autoRehide: String
    let rehideNever: String
    let rehideClickOutside: String
    let rehideSeconds: String
    let rehideCustom: String
    let hoverReveal: String
    let emptyAreaReveal: String
    let scrollReveal: String
    let spacing: String
    let spacingCompact: String
    let spacingStandard: String
    let spacingSpacious: String
    let spacingCustom: String
    let customSpacing: String
    let pinned: String
}

extension FeatureStrings {
    static func menuBarOrganizerAdvanced(_ language: AppLanguage) -> MenuBarOrganizerAdvancedStrings {
        switch language {
        case .ptBR:
            return .init(title: "Recursos avançados", showHidden: "Mostrar itens ocultos", showAll: "Mostrar todos os itens",
                         hideAll: "Ocultar todos os itens", search: "Buscar na menu bar",
                         secondaryBar: "Abrir barra secundária", autoRehide: "Ocultar novamente",
                         rehideNever: "Nunca", rehideClickOutside: "Ao clicar fora",
                         rehideSeconds: "Após %.0f s", rehideCustom: "Duração personalizada",
                         hoverReveal: "Revelar ao passar o cursor",
                         emptyAreaReveal: "Revelar ao clicar em área vazia", scrollReveal: "Revelar ao rolar",
                         spacing: "Espaçamento", spacingCompact: "Compacto", spacingStandard: "Padrão",
                         spacingSpacious: "Espaçado", spacingCustom: "Personalizado",
                         customSpacing: "Espaçamento personalizado",
                         pinned: "Manter barra secundária aberta")
        case .es:
            return .init(title: "Funciones avanzadas", showHidden: "Mostrar elementos ocultos", showAll: "Mostrar todo",
                         hideAll: "Ocultar todo", search: "Buscar en la barra de menús",
                         secondaryBar: "Abrir barra secundaria", autoRehide: "Ocultar de nuevo",
                         rehideNever: "Nunca", rehideClickOutside: "Al hacer clic fuera",
                         rehideSeconds: "Después de %.0f s", rehideCustom: "Duración personalizada",
                         hoverReveal: "Mostrar al pasar el cursor",
                         emptyAreaReveal: "Mostrar al hacer clic en área vacía", scrollReveal: "Mostrar al desplazarse",
                         spacing: "Espaciado", spacingCompact: "Compacto", spacingStandard: "Estándar",
                         spacingSpacious: "Espaciado", spacingCustom: "Personalizado",
                         customSpacing: "Espaciado personalizado", pinned: "Mantener abierta")
        case .fr:
            return .init(title: "Fonctions avancées", showHidden: "Afficher les éléments masqués", showAll: "Tout afficher",
                         hideAll: "Tout masquer", search: "Rechercher dans la barre des menus",
                         secondaryBar: "Ouvrir la barre secondaire", autoRehide: "Masquer à nouveau",
                         rehideNever: "Jamais", rehideClickOutside: "Au clic à l’extérieur",
                         rehideSeconds: "Après %.0f s", rehideCustom: "Durée personnalisée",
                         hoverReveal: "Afficher au survol",
                         emptyAreaReveal: "Afficher au clic dans une zone vide", scrollReveal: "Afficher au défilement",
                         spacing: "Espacement", spacingCompact: "Compact", spacingStandard: "Standard",
                         spacingSpacious: "Espacé", spacingCustom: "Personnalisé",
                         customSpacing: "Espacement personnalisé", pinned: "Garder ouverte")
        default:
            return .init(title: "Advanced behavior", showHidden: "Show hidden items", showAll: "Show all items",
                         hideAll: "Hide all items", search: "Search menu bar",
                         secondaryBar: "Open secondary bar", autoRehide: "Hide again",
                         rehideNever: "Never", rehideClickOutside: "On click outside",
                         rehideSeconds: "After %.0f s", rehideCustom: "Custom duration",
                         hoverReveal: "Reveal on hover",
                         emptyAreaReveal: "Reveal on empty-area click", scrollReveal: "Reveal on scroll",
                         spacing: "Spacing", spacingCompact: "Compact", spacingStandard: "Standard",
                         spacingSpacious: "Spacious", spacingCustom: "Custom",
                         customSpacing: "Custom spacing", pinned: "Keep bar open")
        }
    }
}
