// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum MenuBarOrganizerSection: String, CaseIterable, Codable, Identifiable {
    case visible
    case hidden
    case alwaysHidden

    var id: String { rawValue }
}

enum MenuBarOrganizerPresentationMode: String, CaseIterable {
    case automatic
    case menuBar
    case secondaryBar

    static func sanitized(_ raw: String?) -> Self {
        Self(rawValue: raw ?? "") ?? .automatic
    }
}

enum MenuBarOrganizerRehideMode: String, CaseIterable {
    case never
    case afterDelay
    case focusedApp

    static func sanitized(_ raw: String?) -> Self {
        Self(rawValue: raw ?? "") ?? .afterDelay
    }
}

struct MenuBarOrganizerCapabilities: Equatable {
    let canEnumerate: Bool
    let canMove: Bool
    let canCapture: Bool
    let hasPrivateFrameAPI: Bool

    var automaticEditorAvailable: Bool { canEnumerate && canMove }
}

struct MenuBarItemIdentity: Hashable, Codable {
    let bundleIdentifier: String
    let title: String
    let occurrence: Int

    var storageValue: String {
        [bundleIdentifier, title, String(occurrence)]
            .map { $0.replacingOccurrences(of: "|", with: "||") }
            .joined(separator: "|")
    }
}

struct ManagedMenuBarItem: Identifiable {
    let id: MenuBarItemIdentity
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let bundleIdentifier: String
    let title: String
    let frame: CGRect
    let section: MenuBarOrganizerSection
    let isMovable: Bool
    let isProtected: Bool
    let image: NSImage?

    var displayName: String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty, cleanTitle.caseInsensitiveCompare(ownerName) != .orderedSame {
            return "\(ownerName) — \(cleanTitle)"
        }
        return ownerName.isEmpty ? (cleanTitle.isEmpty ? "Menu bar item" : cleanTitle) : ownerName
    }
}

struct MenuBarOrganizerWindowRecord {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let bundleIdentifier: String
    let title: String
    let frame: CGRect
    let layer: Int
    let alpha: Double
}

enum MenuBarOrganizerSupport {
    static let allowedRehideDelays = [3, 5, 10, 15, 30, 60]

    static func sanitizedRehideDelay(_ value: Int) -> Int {
        allowedRehideDelays.min(by: { abs($0 - value) < abs($1 - value) }) ?? 10
    }

    static func collapsedLength(screenWidths: [CGFloat]) -> CGFloat {
        let widest = screenWidths.max() ?? 2_048
        return min(max(widest * 2, 4_096), 16_384)
    }

    static func section(itemMidX: CGFloat,
                        hiddenDividerMidX: CGFloat?,
                        alwaysHiddenDividerMidX: CGFloat?) -> MenuBarOrganizerSection {
        guard let hiddenX = hiddenDividerMidX else { return .visible }
        if let alwaysX = alwaysHiddenDividerMidX, itemMidX < alwaysX {
            return .alwaysHidden
        }
        if itemMidX < hiddenX {
            return .hidden
        }
        return .visible
    }

    static func identities(for records: [MenuBarOrganizerWindowRecord]) -> [CGWindowID: MenuBarItemIdentity] {
        var occurrences: [String: Int] = [:]
        var result: [CGWindowID: MenuBarItemIdentity] = [:]
        for record in records.sorted(by: {
            if $0.bundleIdentifier != $1.bundleIdentifier {
                return $0.bundleIdentifier < $1.bundleIdentifier
            }
            if $0.title != $1.title { return $0.title < $1.title }
            // Window ids stay stable while an item is reordered. Using x here
            // would swap duplicate identities during the very move being
            // verified.
            return $0.windowID < $1.windowID
        }) {
            let key = "\(record.bundleIdentifier)\u{0}\(record.title)"
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            result[record.windowID] = MenuBarItemIdentity(bundleIdentifier: record.bundleIdentifier,
                                                          title: record.title,
                                                          occurrence: occurrence)
        }
        return result
    }

    static func isLikelyMenuBarWindow(_ record: MenuBarOrganizerWindowRecord,
                                      statusLevel: Int,
                                      screenTopEdges: [CGFloat]) -> Bool {
        guard record.layer == statusLevel,
              record.alpha > 0,
              record.frame.width > 0,
              record.frame.height > 0,
              record.frame.height <= 64
        else { return false }
        return screenTopEdges.contains { abs(record.frame.maxY - $0) <= 8 || abs(record.frame.minY - $0) <= 8 }
            || record.frame.minY <= 8
    }

    static func isSystemImmovable(bundleIdentifier: String, title: String) -> Bool {
        let normalized = title.lowercased()
        if bundleIdentifier == "com.apple.controlcenter" {
            return normalized.contains("clock") || normalized.contains("siri")
        }
        return bundleIdentifier == "com.apple.systemuiserver"
            && (normalized.contains("clock") || normalized.contains("notification"))
    }

    static func shouldUseSecondaryBar(mode: MenuBarOrganizerPresentationMode,
                                      hiddenWidth: CGFloat,
                                      availableWidth: CGFloat,
                                      hasNotch: Bool) -> Bool {
        switch mode {
        case .secondaryBar:
            return true
        case .menuBar:
            return false
        case .automatic:
            return hasNotch || hiddenWidth > max(availableWidth, 0)
        }
    }

    static func orderedItems(_ items: [ManagedMenuBarItem],
                             in section: MenuBarOrganizerSection) -> [ManagedMenuBarItem] {
        items.filter { $0.section == section }.sorted { $0.frame.minX < $1.frame.minX }
    }
}
