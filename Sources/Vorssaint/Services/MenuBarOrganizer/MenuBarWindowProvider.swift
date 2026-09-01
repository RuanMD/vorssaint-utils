// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

final class MenuBarWindowProvider {
    private struct EnumerationResult {
        let records: [MenuBarOrganizerWindowRecord]
        let succeeded: Bool
        let usedPrivateWindowList: Bool
    }

    private let bridge = MenuBarWindowServerBridge.shared
    private let resolver = MenuBarItemSourceResolver()
    private let queue = DispatchQueue(label: "com.vorssaint.menu-bar-enumeration",
                                      qos: .utility)

    func snapshot(hiddenDividerMidX: CGFloat?,
                  alwaysHiddenDividerMidX: CGFloat?,
                  excludedWindowIDs: Set<CGWindowID>) async -> MenuBarItemSnapshot {
        let enumeration = await enumerate()
        let enumeratedRecords = enumeration.records.filter {
            !excludedWindowIDs.contains($0.windowID)
        }
        let catalog = MenuBarOrganizerSupport.deduplicatedSourceCandidates(
            await resolver.discover())
        let resolvedSources = await resolver.resolve(
            records: enumeratedRecords, catalog: catalog)
        // An AX-only candidate has no verified WindowServer target for the
        // Command-drag. Keep it out of the editor until it correlates to a real
        // status-item window instead of rendering it as a locked pseudo-item.
        let records = enumeratedRecords.filter {
            !MenuBarOrganizerSupport.isOrganizerInternalItem(
                record: $0, source: resolvedSources[$0.windowID])
        }
        let sources = resolvedSources.filter { entry in
            records.contains { $0.windowID == entry.key }
        }
        let identities = MenuBarOrganizerSupport.identities(for: records, sources: sources)
        let currentPID = ProcessInfo.processInfo.processIdentifier

        let items = await MainActor.run {
            records.compactMap { record -> ManagedMenuBarItem? in
                guard let resolved = identities[record.windowID] else { return nil }
                let source = resolved.source
                let bundleIdentifier = source?.bundleIdentifier
                    ?? record.ownerBundleIdentifier
                let title = MenuBarOrganizerSupport.userFacingTitle(
                    source: source, recordTitle: record.title)
                let protected = source?.pid == currentPID
                    || MenuBarOrganizerSupport.isSystemImmovable(
                        bundleIdentifier: bundleIdentifier,
                        title: title)
                let movable = (resolved.state == .stable
                    || (source != nil
                        && source?.bundleIdentifier
                            != MenuBarOrganizerSupport.controlCenterBundleIdentifier))
                    && !protected
                let sourceApp = source.flatMap { NSRunningApplication(processIdentifier: $0.pid) }
                let ownerApp = NSRunningApplication(processIdentifier: record.ownerPID)
                let iconApp = sourceApp ?? ownerApp
                // NSRunningApplication.icon is the high-res app icon sourced
                // directly from the bundle; prefer it over the NSWorkspace path
                // which can return lower-quality or wrong icons for hosted items.
                let icon: NSImage? = iconApp?.icon
                    ?? iconApp?.bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
                    ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
                        .map { NSWorkspace.shared.icon(forFile: $0.path) }
                return ManagedMenuBarItem(
                    id: resolved.id,
                    windowID: record.windowID,
                    ownerPID: record.ownerPID,
                    ownerBundleIdentifier: record.ownerBundleIdentifier,
                    sourcePID: source?.pid,
                    ownerName: record.ownerName,
                    sourceName: source?.name ?? record.ownerName,
                    bundleIdentifier: bundleIdentifier,
                    title: title,
                    frame: record.frame,
                    section: MenuBarOrganizerSupport.section(
                        itemMidX: record.frame.midX,
                        hiddenDividerMidX: hiddenDividerMidX,
                        alwaysHiddenDividerMidX: alwaysHiddenDividerMidX),
                    identityState: resolved.state,
                    isMovable: movable,
                    isProtected: protected,
                    image: icon)
            }
            .sorted {
                if $0.frame.minX == $1.frame.minX {
                    return $0.id.storageValue < $1.id.storageValue
                }
                return $0.frame.minX < $1.frame.minX
            }
        }

        return MenuBarItemSnapshot(
            items: items,
            capabilities: MenuBarOrganizerCapabilities(
                canEnumerate: enumeration.succeeded || !catalog.isEmpty,
                canMove: AXIsProcessTrusted(),
                hasPrivateWindowList: enumeration.usedPrivateWindowList,
                unresolvedItemCount: items.count {
                    $0.identityState == .provisional
                },
                moveAvailabilityCounts: MenuBarOrganizerSupport.moveAvailabilityCounts(
                    for: items)),
            enumerationSucceeded: enumeration.succeeded || !catalog.isEmpty)
    }

    func invalidateIdentityCache() async {
        await resolver.invalidate()
    }

    private func enumerate() async -> EnumerationResult {
        await withCheckedContinuation { continuation in
            queue.async { [bridge] in
                continuation.resume(returning: Self.enumerate(using: bridge))
            }
        }
    }

    private static func enumerate(
        using bridge: MenuBarWindowServerBridge
    ) -> EnumerationResult {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(
            options, kCGNullWindowID) as? [[String: Any]]
        else {
            return EnumerationResult(records: [],
                                     succeeded: false,
                                     usedPrivateWindowList: false)
        }

        let privateIDs = bridge.menuBarWindowIDs()
        let privateIDSet = privateIDs.map(Set.init)
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        CGGetActiveDisplayList(UInt32(displays.count), &displays, &displayCount)
        let topEdges = displays.prefix(Int(displayCount)).flatMap {
            let bounds = CGDisplayBounds($0)
            return [bounds.minY, bounds.maxY]
        }

        var records = raw.compactMap {
            record(from: $0, bridge: bridge)
        }
        records = records.filter {
            MenuBarOrganizerSupport.isMenuBarItemCandidate(
                $0, mainMenuLevel: mainMenuLevel)
        }
        let privateRecords = privateIDSet.map { ids in
            records.filter { ids.contains($0.windowID) }
        } ?? []
        let publicRecords = records.filter {
            MenuBarOrganizerSupport.isLikelyMenuBarWindow(
                $0, statusLevel: statusLevel, screenTopEdges: topEdges)
        }
        records = MenuBarOrganizerSupport.mergedMenuBarWindowRecords(
            privateRecords: privateRecords,
            publicRecords: publicRecords)
        records = MenuBarOrganizerSupport.normalizedMenuBarWindowRecords(
            records, statusLevel: statusLevel)

        return EnumerationResult(
            records: records,
            succeeded: privateIDs != nil || !records.isEmpty,
            usedPrivateWindowList: privateIDs != nil)
    }

    private static func record(
        from dictionary: [String: Any],
        bridge: MenuBarWindowServerBridge
    ) -> MenuBarOrganizerWindowRecord? {
        guard let idNumber = dictionary[kCGWindowNumber as String] as? NSNumber,
              let pidNumber = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
              let bounds = dictionary[kCGWindowBounds as String] as? NSDictionary,
              let fallbackFrame = CGRect(dictionaryRepresentation: bounds)
        else { return nil }

        let windowID = CGWindowID(idNumber.uint32Value)
        let pid = pid_t(pidNumber.int32Value)
        let application = NSRunningApplication(processIdentifier: pid)
        let ownerName = (dictionary[kCGWindowOwnerName as String] as? String)
            ?? application?.localizedName
            ?? ""
        let level = bridge.level(for: windowID)
            ?? CGWindowLevel((dictionary[kCGWindowLayer as String] as? NSNumber)?.int32Value ?? 0)
        return MenuBarOrganizerWindowRecord(
            windowID: windowID,
            ownerPID: pid,
            ownerName: ownerName,
            ownerBundleIdentifier: application?.bundleIdentifier ?? "",
            title: dictionary[kCGWindowName as String] as? String ?? "",
            frame: bridge.frame(for: windowID) ?? fallbackFrame,
            layer: Int(level),
            alpha: (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
            isOnScreen: (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false)
    }
}
