// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MenuBarRevealTrigger: String, CaseIterable, Codable, Identifiable {
    case statusItem
    case globalShortcut
    case hover
    case emptyAreaClick
    case scroll

    var id: String { rawValue }
}

enum MenuBarRehidePolicy: Equatable, Codable {
    case never
    case clickOutside
    case afterSeconds(Double)

    static let defaultDelay: Double = 5
    static let allowedDelays: [Double] = [3, 5, 10, 30]

    var storageValue: String {
        switch self {
        case .never: return "never"
        case .clickOutside: return "clickOutside"
        case .afterSeconds(let seconds): return "seconds:\(Self.sanitizeDelay(seconds))"
        }
    }

    static func fromStorage(_ raw: String?) -> Self {
        guard let raw else { return .afterSeconds(defaultDelay) }
        if raw == "never" { return .never }
        if raw == "clickOutside" { return .clickOutside }
        guard raw.hasPrefix("seconds:"),
              let seconds = Double(raw.dropFirst("seconds:".count))
        else { return .afterSeconds(defaultDelay) }
        return .afterSeconds(sanitizeDelay(seconds))
    }

    static func sanitizeDelay(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return defaultDelay }
        return min(max(seconds, 1), 300)
    }
}

enum MenuBarSpacingPreset: String, CaseIterable, Codable, Identifiable {
    case compact
    case standard
    case spacious
    case custom

    var id: String { rawValue }

    var defaultValue: Double {
        switch self {
        case .compact: return 2
        case .standard: return 6
        case .spacious: return 10
        case .custom: return 6
        }
    }
}

enum MenuBarOrganizerAdvancedSupport {
    static let minimumSpacing: Double = 0
    static let maximumSpacing: Double = 24

    static func sanitizedSpacing(_ value: Double) -> Double {
        guard value.isFinite else { return MenuBarSpacingPreset.standard.defaultValue }
        return min(max(value, minimumSpacing), maximumSpacing)
    }

    static func effectiveSpacing(preset: MenuBarSpacingPreset, custom: Double) -> Double {
        preset == .custom ? sanitizedSpacing(custom) : preset.defaultValue
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchScore(query: String, name: String) -> Int? {
        let needle = normalized(query)
        let haystack = normalized(name)
        guard !needle.isEmpty, !haystack.isEmpty else { return nil }
        if needle == haystack { return 1_000 }
        if haystack.hasPrefix(needle) { return 800 - haystack.count }
        if haystack.split(whereSeparator: { $0 == " " || $0 == "-" }).contains(where: {
            $0.hasPrefix(needle)
        }) { return 600 - haystack.count }
        guard haystack.contains(needle) else { return nil }
        return 400 - haystack.count
    }

    static func search(_ query: String,
                       items: [ManagedMenuBarItem]) -> [ManagedMenuBarItem] {
        let scored: [(item: ManagedMenuBarItem, score: Int)] = items.compactMap { item in
            let names = [item.displayName, item.sourceName, item.title]
            let score = names.compactMap { matchScore(query: query, name: $0) }.max()
            guard score != nil else { return nil }
            return (item, score ?? 0)
        }
        return scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.item.displayName.localizedCaseInsensitiveCompare($1.item.displayName)
                == .orderedAscending
        }
        .map(\.item)
    }

    static func shouldRehide(now: Date,
                             deadline: Date?,
                             pointerInside: Bool,
                             menuOpen: Bool,
                             interactionInProgress: Bool) -> Bool {
        guard let deadline, now >= deadline else { return false }
        return !pointerInside && !menuOpen && !interactionInProgress
    }
}
