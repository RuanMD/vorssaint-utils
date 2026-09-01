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

enum MenuBarItemIdentityState: String, Codable {
    case stable
    case provisional
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

struct MenuBarItemSourceIdentity: Equatable {
    let pid: pid_t
    let bundleIdentifier: String
    let name: String
    let axIdentifier: String?
    let axTitle: String?

    var stableTitle: String? {
        let identifier = axIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !identifier.isEmpty { return identifier }
        let title = axTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }

    /// Accessibility identifiers are excellent persistence keys but are usually
    /// implementation details (for example `com.example.app.status`). Keep them
    /// out of the UI and prefer the accessibility title when one is available.
    var displayTitle: String? {
        let title = axTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, !MenuBarOrganizerSupport.isTechnicalIdentifier(title)
        else { return nil }
        return title
    }
}

/// An Accessibility status item. It can exist even when the WindowServer only
/// exposes the whole composited menu bar instead of an individual CG window.
struct MenuBarItemSourceCandidate: Equatable {
    let source: MenuBarItemSourceIdentity
    let frame: CGRect

    var slotKey: String {
        "\(source.pid):\(source.bundleIdentifier):"
            + (source.axIdentifier ?? source.axTitle ?? source.name)
            + ":\(Int(frame.minX)): \(Int(frame.minY))"
    }
}

struct ResolvedMenuBarItemIdentity {
    let id: MenuBarItemIdentity
    let state: MenuBarItemIdentityState
    let source: MenuBarItemSourceIdentity?
}

struct ManagedMenuBarItem: Identifiable {
    let id: MenuBarItemIdentity
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerBundleIdentifier: String
    let sourcePID: pid_t?
    let ownerName: String
    let sourceName: String
    let bundleIdentifier: String
    let title: String
    let frame: CGRect
    let section: MenuBarOrganizerSection
    let identityState: MenuBarItemIdentityState
    let isMovable: Bool
    let isProtected: Bool
    let image: NSImage?

    var displayName: String {
        let cleanTitle = MenuBarOrganizerSupport.userFacingTitle(title)
        let appName = sourceName.isEmpty ? ownerName : sourceName
        if !cleanTitle.isEmpty, cleanTitle.caseInsensitiveCompare(appName) != .orderedSame {
            return appName.isEmpty ? cleanTitle : "\(appName) - \(cleanTitle)"
        }
        return appName.isEmpty ? (cleanTitle.isEmpty ? "Menu bar item" : cleanTitle) : appName
    }
}

struct MenuBarOrganizerWindowRecord: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let ownerBundleIdentifier: String
    let title: String
    let frame: CGRect
    let layer: Int
    let alpha: Double
    let isOnScreen: Bool
}

struct MenuBarOrganizerCapabilities: Equatable {
    let canEnumerate: Bool
    let canMove: Bool
    let hasPrivateWindowList: Bool
    let unresolvedItemCount: Int

    var automaticEditorAvailable: Bool {
        canEnumerate && canMove
    }
}

struct MenuBarItemSnapshot {
    let items: [ManagedMenuBarItem]
    let capabilities: MenuBarOrganizerCapabilities
    let enumerationSucceeded: Bool
}

enum MenuBarOrganizerSupport {
    static let controlCenterBundleIdentifier = "com.apple.controlcenter"
    static let systemUIServerBundleIdentifier = "com.apple.systemuiserver"

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

    static func identities(
        for records: [MenuBarOrganizerWindowRecord],
        sources: [CGWindowID: MenuBarItemSourceIdentity]
    ) -> [CGWindowID: ResolvedMenuBarItemIdentity] {
        struct Seed {
            let record: MenuBarOrganizerWindowRecord
            let source: MenuBarItemSourceIdentity?
            let namespace: String
            let title: String
            let state: MenuBarItemIdentityState
        }

        let seeds = records.map { record -> Seed in
            let source = sources[record.windowID]
            let isHosted = record.ownerBundleIdentifier == controlCenterBundleIdentifier
            // A generic Control Center AX child proves only which process hosts
            // the window. It does not prove which third-party app created the
            // status item, so never promote that host fallback to a stable
            // persisted identity.
            let sourceIsOnlyHost = isHosted
                && source?.bundleIdentifier == controlCenterBundleIdentifier
                && isGenericControlCenterHostedTitle(record.title)
            let resolvedSource = sourceIsOnlyHost ? nil : source
            let state: MenuBarItemIdentityState = isHosted
                && (resolvedSource == nil || resolvedSource?.stableTitle == nil)
                ? .provisional
                : .stable
            let namespace = resolvedSource?.bundleIdentifier.nonEmpty
                ?? record.ownerBundleIdentifier.nonEmpty
                ?? "pid:\(record.ownerPID)"
            let title = resolvedSource?.stableTitle?.nonEmpty
                ?? record.title.nonEmpty
                ?? record.ownerName.nonEmpty
                ?? "window:\(record.windowID)"
            return Seed(record: record,
                        source: resolvedSource,
                        namespace: namespace,
                        title: title,
                        state: state)
        }

        var occurrences: [String: Int] = [:]
        var result: [CGWindowID: ResolvedMenuBarItemIdentity] = [:]
        for seed in seeds.sorted(by: {
            if $0.namespace != $1.namespace { return $0.namespace < $1.namespace }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.record.windowID < $1.record.windowID
        }) {
            let key = "\(seed.namespace)\u{0}\(seed.title)"
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            result[seed.record.windowID] = ResolvedMenuBarItemIdentity(
                id: MenuBarItemIdentity(bundleIdentifier: seed.namespace,
                                        title: seed.title,
                                        occurrence: occurrence),
                state: seed.state,
                source: seed.source)
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
        return screenTopEdges.contains {
            abs(record.frame.maxY - $0) <= 8 || abs(record.frame.minY - $0) <= 8
        } || record.frame.minY <= 8
    }

    static func isMenuBarItemCandidate(_ record: MenuBarOrganizerWindowRecord,
                                       mainMenuLevel: Int) -> Bool {
        record.layer != mainMenuLevel
            && !(record.ownerName == "Window Server"
                && record.title.caseInsensitiveCompare("Menubar") == .orderedSame)
    }

    /// Joins the private probe with the public WindowServer candidates. The
    /// private API is useful for items that the public geometry heuristic cannot
    /// see, but on some macOS releases it returns only a subset of the menu bar.
    /// Therefore it must never be used as an exclusive filter.
    static func mergedMenuBarWindowRecords(
        privateRecords: [MenuBarOrganizerWindowRecord],
        publicRecords: [MenuBarOrganizerWindowRecord]
    ) -> [MenuBarOrganizerWindowRecord] {
        var seen = Set<CGWindowID>()
        return (privateRecords + publicRecords).filter { seen.insert($0.windowID).inserted }
    }

    static func deduplicatedSourceCandidates(
        _ candidates: [MenuBarItemSourceCandidate]
    ) -> [MenuBarItemSourceCandidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.slotKey).inserted }
    }

    static func isOrganizerInternalItem(
        record: MenuBarOrganizerWindowRecord,
        source: MenuBarItemSourceIdentity?
    ) -> Bool {
        [record.title, source?.axIdentifier, source?.axTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { $0.hasPrefix("Vorssaint.MenuBarOrganizer.") }
    }

    static func isOrganizerInternalSource(_ source: MenuBarItemSourceIdentity) -> Bool {
        [source.axIdentifier, source.axTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { $0.hasPrefix("Vorssaint.MenuBarOrganizer.") }
    }

    static func isTechnicalIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("Vorssaint.MenuBarOrganizer.") { return true }
        return trimmed.range(
            of: #"^[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*){2,}$"#,
            options: .regularExpression
        ) != nil
    }

    static func userFacingTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return isTechnicalIdentifier(trimmed) ? "" : trimmed
    }

    static func userFacingTitle(
        source: MenuBarItemSourceIdentity?,
        recordTitle: String
    ) -> String {
        if let title = source?.displayTitle { return title }
        return userFacingTitle(recordTitle)
    }

    static func frameMatchScore(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat? {
        guard lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else { return nil }
        let centerDistance = hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
        let sizeDistance = abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
        let intersection = lhs.intersection(rhs)
        let overlap = intersection.isNull
            ? 0
            : (intersection.width * intersection.height) / max(lhs.width * lhs.height, 1)
        guard centerDistance <= 5 || overlap >= 0.72 else { return nil }
        return centerDistance + sizeDistance * 0.25 - overlap
    }

    static func isGenericControlCenterHostedTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty
            || normalized.range(of: #"^Item-\d+$"#,
                                options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Synthetic events must go to the process that owns the window under the
    /// pointer. On macOS 26 that is commonly Control Center, not the app that
    /// logically created the status item.
    static func eventTargetPID(ownerPID: pid_t,
                               ownerBundleIdentifier: String,
                               sourcePID: pid_t?) -> pid_t {
        if ownerBundleIdentifier == controlCenterBundleIdentifier {
            return ownerPID
        }
        return sourcePID ?? ownerPID
    }

    static func isSystemImmovable(bundleIdentifier: String, title: String) -> Bool {
        let normalized = title.lowercased()
        if bundleIdentifier == controlCenterBundleIdentifier {
            return normalized.contains("clock")
                || normalized.contains("siri")
                || isGenericControlCenterHostedTitle(title)
        }
        return bundleIdentifier == systemUIServerBundleIdentifier
            && (normalized.contains("clock") || normalized.contains("notification"))
    }

    static func shouldKeepPreviousSnapshot(previousCount: Int,
                                           newCount: Int,
                                           enumerationSucceeded: Bool) -> Bool {
        previousCount > 0 && (!enumerationSucceeded || newCount == 0)
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
        items.filter { $0.section == section }.sorted {
            if $0.frame.minX == $1.frame.minX {
                return $0.id.storageValue < $1.id.storageValue
            }
            return $0.frame.minX < $1.frame.minX
        }
    }

    /// Retorna rótulos legíveis quando vários status items usam o mesmo
    /// fallback de app/título. O sufixo deriva da identidade estável, nunca de
    /// PID ou identificador do WindowServer.
    static func displayNames(for items: [ManagedMenuBarItem]) -> [MenuBarItemIdentity: String] {
        let grouped = Dictionary(grouping: items) { item in
            item.displayName.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                     locale: Locale(identifier: "en_US_POSIX"))
                .lowercased()
        }
        var labels: [MenuBarItemIdentity: String] = [:]
        var usedLabels = Set<String>()
        for key in grouped.keys.sorted() {
            guard let group = grouped[key] else { continue }
            let ordered = group.sorted { $0.id.storageValue < $1.id.storageValue }
            for (index, item) in ordered.enumerated() {
                let preferred = ordered.count > 1
                    ? "\(item.displayName) #\(index + 1)"
                    : item.displayName
                var label = preferred
                var suffix = 2
                while usedLabels.contains(normalizedLabel(label)) {
                    label = "\(preferred) #\(suffix)"
                    suffix += 1
                }
                usedLabels.insert(normalizedLabel(label))
                labels[item.id] = label
            }
        }
        return labels
    }

    private static func normalizedLabel(_ label: String) -> String {
        label.folding(options: [.diacriticInsensitive, .caseInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    static func displayName(for item: ManagedMenuBarItem,
                            among items: [ManagedMenuBarItem]) -> String {
        displayNames(for: items)[item.id] ?? item.displayName
    }

    /// Um único Command-drag desloca os frames vizinhos quando a menu bar
    /// reorganiza o espaço. Compara as identidades ordenadas sem o item arrastado
    /// para aceitar esses deslocamentos e rejeitar uma segunda alteração.
    static func isSingleItemMove(before: [ManagedMenuBarItem],
                                 after: [ManagedMenuBarItem],
                                 movingItemID: MenuBarItemIdentity,
                                 destination: MenuBarOrganizerSection) -> Bool {
        let beforeIDs = before.map(\.id)
        let afterIDs = after.map(\.id)
        let beforeWindowIDs = before.map(\.windowID)
        let afterWindowIDs = after.map(\.windowID)
        guard let beforeMoving = before.first(where: { $0.id == movingItemID }),
              let afterMoving = after.first(where: { $0.id == movingItemID }),
              afterMoving.section == destination,
              beforeIDs.count == Set(beforeIDs).count,
              afterIDs.count == Set(afterIDs).count,
              beforeWindowIDs.count == Set(beforeWindowIDs).count,
              afterWindowIDs.count == Set(afterWindowIDs).count,
              beforeIDs.count == afterIDs.count,
              Set(beforeIDs) == Set(afterIDs),
              beforeMoving.id == afterMoving.id
        else { return false }

        let sections = MenuBarOrganizerSection.allCases
        for section in sections {
            let beforeIDs = orderedItems(before, in: section)
                .map(\.id)
                .filter { $0 != movingItemID }
            let afterIDs = orderedItems(after, in: section)
                .map(\.id)
                .filter { $0 != movingItemID }
            guard beforeIDs == afterIDs else { return false }
        }

        if beforeMoving.section == destination,
           orderedItems(before, in: destination).map(\.id)
                == orderedItems(after, in: destination).map(\.id) {
            return false
        }

        return true
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
