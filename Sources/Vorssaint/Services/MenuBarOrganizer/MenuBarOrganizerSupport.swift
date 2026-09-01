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

enum MenuBarItemMoveAvailability: Equatable {
    case movable
    case provisionalIdentity
    case protected
    case windowTargetUnavailable
}

struct MenuBarItemMoveAvailabilityCounts: Equatable {
    let movable: Int
    let provisionalIdentity: Int
    let protected: Int
    let windowTargetUnavailable: Int

    var locked: Int {
        provisionalIdentity + protected + windowTargetUnavailable
    }
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
    /// CGWindowID obtained via _AXUIElementGetWindow; nil when the private API
    /// is unavailable or the element has no backing CoreGraphics window yet.
    let windowID: CGWindowID?

    var slotKey: String {
        "\(source.pid):\(source.bundleIdentifier):"
            + (source.axIdentifier ?? source.axTitle ?? source.name)
            + ":\(Int(frame.minX)):\(Int(frame.minY))"
    }

    init(source: MenuBarItemSourceIdentity,
         frame: CGRect,
         windowID: CGWindowID? = nil) {
        self.source = source
        self.frame = frame
        self.windowID = windowID
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

    var moveAvailability: MenuBarItemMoveAvailability {
        if isProtected { return .protected }
        if identityState == .provisional { return .provisionalIdentity }
        return isMovable ? .movable : .windowTargetUnavailable
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
    let moveAvailabilityCounts: MenuBarItemMoveAvailabilityCounts

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
            let hasConcreteAX = source != nil && source?.stableTitle != nil
                && !isGenericControlCenterHostedTitle(source?.stableTitle ?? "")
            // A generic Control Center AX child proves only which process hosts
            // the window. When an item has concrete AX title/identifier, use it.
            let sourceIsOnlyHost = isHosted
                && source?.bundleIdentifier == controlCenterBundleIdentifier
                && (isGenericControlCenterHostedTitle(record.title) || isGenericControlCenterHostedTitle(source?.stableTitle ?? ""))
                && !hasConcreteAX
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
        let allowedLevels = [statusLevel, 101, 24, 25]
        guard allowedLevels.contains(record.layer),
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

    static func normalizedMenuBarWindowRecords(
        _ records: [MenuBarOrganizerWindowRecord],
        statusLevel: Int
    ) -> [MenuBarOrganizerWindowRecord] {
        var normalized: [MenuBarOrganizerWindowRecord] = []
        for record in records {
            guard let index = normalized.firstIndex(where: {
                samePhysicalSlot($0, record)
            }) else {
                normalized.append(record)
                continue
            }
            if preferredWindowRecord(record, over: normalized[index], statusLevel: statusLevel) {
                normalized[index] = record
            }
        }
        return normalized
    }

    static func deduplicatedSourceCandidates(
        _ candidates: [MenuBarItemSourceCandidate]
    ) -> [MenuBarItemSourceCandidate] {
        var result: [MenuBarItemSourceCandidate] = []
        for candidate in candidates {
            guard let index = result.firstIndex(where: {
                sameSourceCandidate($0, candidate)
            }) else {
                result.append(candidate)
                continue
            }
            if candidate.windowID != nil, result[index].windowID == nil {
                result[index] = candidate
            }
        }
        return result
    }

    static func isSemanticallySameItem(
        _ lhs: ManagedMenuBarItem,
        _ rhs: ManagedMenuBarItem
    ) -> Bool {
        guard itemBundleIdentifier(lhs) == itemBundleIdentifier(rhs) else {
            return false
        }
        let leftTitle = normalizedItemTitle(lhs)
        let rightTitle = normalizedItemTitle(rhs)
        return leftTitle.isEmpty || rightTitle.isEmpty || leftTitle == rightTitle
    }

    static func item(
        matching identity: MenuBarItemIdentity,
        in items: [ManagedMenuBarItem]
    ) -> ManagedMenuBarItem? {
        if let exact = items.first(where: { $0.id == identity }) {
            return exact
        }
        return items
            .filter {
                $0.id.bundleIdentifier == identity.bundleIdentifier
                    && $0.id.title == identity.title
            }
            .sorted { $0.id.occurrence < $1.id.occurrence }
            .first
    }

    static func equivalentItem(
        to item: ManagedMenuBarItem,
        in items: [ManagedMenuBarItem],
        requiringFrameProximity: Bool = false
    ) -> ManagedMenuBarItem? {
        if let exact = items.first(where: { $0.id == item.id }) {
            return exact
        }
        return items
            .filter { candidate in
                guard isSemanticallySameItem(item, candidate) else { return false }
                return !requiringFrameProximity
                    || frameMatchScore(item.frame, candidate.frame) != nil
            }
            .min {
                itemMatchCost(item, $0) < itemMatchCost(item, $1)
            }
    }

    static func semanticMoveMatch(
        before: ManagedMenuBarItem,
        after: [ManagedMenuBarItem],
        excluding excluded: Set<CGWindowID>
    ) -> ManagedMenuBarItem? {
        after
            .filter { !excluded.contains($0.windowID) && isSemanticallySameItem(before, $0) }
            .min {
                if $0.id == before.id { return true }
                if $1.id == before.id { return false }
                return itemMatchCost(before, $0) < itemMatchCost(before, $1)
            }
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
        guard centerDistance <= 12 || overlap >= 0.72 else { return nil }
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
            return normalized.contains("clock") || normalized.contains("siri")
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

    static func moveAvailabilityCounts(
        for items: [ManagedMenuBarItem]
    ) -> MenuBarItemMoveAvailabilityCounts {
        var counts = MenuBarItemMoveAvailabilityCounts(
            movable: 0,
            provisionalIdentity: 0,
            protected: 0,
            windowTargetUnavailable: 0)
        for item in items {
            switch item.moveAvailability {
            case .movable:
                counts = MenuBarItemMoveAvailabilityCounts(
                    movable: counts.movable + 1,
                    provisionalIdentity: counts.provisionalIdentity,
                    protected: counts.protected,
                    windowTargetUnavailable: counts.windowTargetUnavailable)
            case .provisionalIdentity:
                counts = MenuBarItemMoveAvailabilityCounts(
                    movable: counts.movable,
                    provisionalIdentity: counts.provisionalIdentity + 1,
                    protected: counts.protected,
                    windowTargetUnavailable: counts.windowTargetUnavailable)
            case .protected:
                counts = MenuBarItemMoveAvailabilityCounts(
                    movable: counts.movable,
                    provisionalIdentity: counts.provisionalIdentity,
                    protected: counts.protected + 1,
                    windowTargetUnavailable: counts.windowTargetUnavailable)
            case .windowTargetUnavailable:
                counts = MenuBarItemMoveAvailabilityCounts(
                    movable: counts.movable,
                    provisionalIdentity: counts.provisionalIdentity,
                    protected: counts.protected,
                    windowTargetUnavailable: counts.windowTargetUnavailable + 1)
            }
        }
        return counts
    }

    private static func samePhysicalSlot(
        _ lhs: MenuBarOrganizerWindowRecord,
        _ rhs: MenuBarOrganizerWindowRecord
    ) -> Bool {
        guard lhs.ownerPID == rhs.ownerPID,
              normalizedRecordBundle(lhs) == normalizedRecordBundle(rhs),
              normalizedRecordTitle(lhs) == normalizedRecordTitle(rhs)
        else { return false }
        return frameMatchScore(lhs.frame, rhs.frame) != nil
    }

    private static func preferredWindowRecord(
        _ lhs: MenuBarOrganizerWindowRecord,
        over rhs: MenuBarOrganizerWindowRecord,
        statusLevel: Int
    ) -> Bool {
        let lhsStatus = lhs.layer == statusLevel
        let rhsStatus = rhs.layer == statusLevel
        if lhsStatus != rhsStatus { return lhsStatus }
        if lhs.isOnScreen != rhs.isOnScreen { return lhs.isOnScreen }
        if lhs.alpha != rhs.alpha { return lhs.alpha > rhs.alpha }
        let lhsArea = lhs.frame.width * lhs.frame.height
        let rhsArea = rhs.frame.width * rhs.frame.height
        if lhsArea != rhsArea { return lhsArea < rhsArea }
        return lhs.windowID < rhs.windowID
    }

    private static func sameSourceCandidate(
        _ lhs: MenuBarItemSourceCandidate,
        _ rhs: MenuBarItemSourceCandidate
    ) -> Bool {
        guard lhs.source.pid == rhs.source.pid,
              lhs.source.bundleIdentifier == rhs.source.bundleIdentifier
        else { return false }
        if let lhsIdentifier = stableSourceIdentifier(lhs.source),
           let rhsIdentifier = stableSourceIdentifier(rhs.source) {
            return lhsIdentifier == rhsIdentifier
        }
        let lhsTitle = normalizedSourceTitle(lhs.source)
        let rhsTitle = normalizedSourceTitle(rhs.source)
        guard !lhsTitle.isEmpty, lhsTitle == rhsTitle else { return false }
        return frameMatchScore(lhs.frame, rhs.frame) != nil
    }

    private static func stableSourceIdentifier(
        _ source: MenuBarItemSourceIdentity
    ) -> String? {
        let identifier = source.axIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return identifier.isEmpty ? nil : identifier
    }

    private static func normalizedRecordBundle(
        _ record: MenuBarOrganizerWindowRecord
    ) -> String {
        record.ownerBundleIdentifier.isEmpty
            ? "pid:\(record.ownerPID)"
            : record.ownerBundleIdentifier
    }

    private static func normalizedRecordTitle(
        _ record: MenuBarOrganizerWindowRecord
    ) -> String {
        let title = userFacingTitle(record.title).lowercased()
        return title.isEmpty ? record.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : title
    }

    private static func normalizedSourceTitle(
        _ source: MenuBarItemSourceIdentity
    ) -> String {
        (source.axTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func itemBundleIdentifier(_ item: ManagedMenuBarItem) -> String {
        item.id.bundleIdentifier.isEmpty ? item.bundleIdentifier : item.id.bundleIdentifier
    }

    private static func normalizedItemTitle(_ item: ManagedMenuBarItem) -> String {
        let title = item.id.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return title.isEmpty ? item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : title
    }

    private static func itemMatchCost(
        _ lhs: ManagedMenuBarItem,
        _ rhs: ManagedMenuBarItem
    ) -> CGFloat {
        hypot(lhs.frame.midX - rhs.frame.midX, lhs.frame.midY - rhs.frame.midY)
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

    static func isEditorVisible(_ item: ManagedMenuBarItem) -> Bool {
        item.isMovable || item.isProtected
    }

    /// Compara a entidade arrastada por fonte e título, não pelo ID volátil da janela.
    static func isSingleItemMove(before: [ManagedMenuBarItem],
                                 after: [ManagedMenuBarItem],
                                 movingItemID: MenuBarItemIdentity,
                                 destination: MenuBarOrganizerSection) -> Bool {
        let beforeWindowIDs = before.map(\.windowID)
        let afterWindowIDs = after.map(\.windowID)
        guard before.count == after.count,
              beforeWindowIDs.count == Set(beforeWindowIDs).count,
              afterWindowIDs.count == Set(afterWindowIDs).count,
              let beforeMoving = before.first(where: { $0.id == movingItemID })
        else { return false }

        let movingCandidates = after.filter {
            isSemanticallySameItem(beforeMoving, $0) && $0.section == destination
        }
        guard let afterMoving = movingCandidates.first(where: { $0.id == movingItemID })
                ?? movingCandidates.min(by: {
                    itemMatchCost(beforeMoving, $0) < itemMatchCost(beforeMoving, $1)
                })
        else { return false }

        var usedWindowIDs = Set([afterMoving.windowID])
        var mapping: [MenuBarItemIdentity: ManagedMenuBarItem] = [
            beforeMoving.id: afterMoving
        ]
        for item in before where item.id != beforeMoving.id {
            let candidates = after.filter {
                !usedWindowIDs.contains($0.windowID)
                    && isSemanticallySameItem(item, $0)
            }
            guard let match = candidates.first(where: { $0.id == item.id })
                    ?? candidates.min(by: {
                        itemMatchCost(item, $0) < itemMatchCost(item, $1)
                    })
            else { return false }
            usedWindowIDs.insert(match.windowID)
            mapping[item.id] = match
            guard match.section == item.section else { return false }
        }

        for section in MenuBarOrganizerSection.allCases {
            let beforeIDs = orderedItems(before, in: section)
                .map(\.id)
                .filter { $0 != beforeMoving.id }
            let afterIDs = orderedItems(after, in: section)
                .compactMap { candidate in
                    mapping.first(where: { $0.value.id == candidate.id })?.key
                }
                .filter { $0 != beforeMoving.id }
            guard beforeIDs == afterIDs else { return false }
        }

        if beforeMoving.section == destination {
            let beforeOrder = orderedItems(before, in: destination).map(\.id)
            let afterOrder = orderedItems(after, in: destination).compactMap { candidate in
                mapping.first(where: { entry in
                    entry.value.id == candidate.id
                })?.key
            }
            guard beforeOrder != afterOrder else { return false }
        }
        return true
    }


}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
