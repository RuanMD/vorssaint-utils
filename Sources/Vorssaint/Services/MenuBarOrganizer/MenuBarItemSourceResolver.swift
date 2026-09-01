// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Foundation

// MARK: - Private AX → CGWindowID bridge

/// Resolves the CGWindowID that backs an AX element. Used to correlate AX
/// status-item candidates with their WindowServer windows on macOS 26 where
/// Control Center may composite the whole status bar into one surface.
private typealias AXGetWindowFn =
    @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private let _axGetWindow: AXGetWindowFn? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow")
    else { return nil }
    return unsafeBitCast(sym, to: AXGetWindowFn.self)
}()

/// Resolves the app that created each status item. On macOS 26 the WindowServer
/// owner is commonly Control Center, so owner PID alone is not a stable item
/// identity. AX work runs away from the main actor and is bounded by the app's
/// process-wide AX timeout.
actor MenuBarItemSourceResolver {
    private struct ApplicationRecord: Sendable {
        let pid: pid_t
        let bundleIdentifier: String
        let name: String
    }

    private var cache: [CGWindowID: MenuBarItemSourceIdentity] = [:]
    private var catalogCache: [MenuBarItemSourceCandidate] = []
    private var catalogTask: Task<[MenuBarItemSourceCandidate], Never>?
    private var catalogUpdatedAt: Date?

    /// Accessibility is the canonical source for items that macOS 26 renders
    /// into one composited menu-bar surface. Cache it briefly: Settings refreshes
    /// often while the user drags, and walking every app must remain bounded.
    func discover() async -> [MenuBarItemSourceCandidate] {
        guard AXIsProcessTrusted() else { return [] }
        if let catalogUpdatedAt,
           Date().timeIntervalSince(catalogUpdatedAt) < 5 {
            return catalogCache
        }
        let applications = await runningApplications()
        if catalogTask == nil {
            catalogTask = Task.detached(priority: .utility) {
                var candidates: [MenuBarItemSourceCandidate] = []
                for application in applications {
                    guard !Task.isCancelled else { return [] }
                    candidates.append(contentsOf: Self.scanExtrasMenuBar(application))
                }
                return candidates
            }
        }
        guard let catalogTask else { return catalogCache }
        let candidates = await catalogTask.value
        self.catalogTask = nil
        guard !Task.isCancelled else { return catalogCache }
        catalogCache = candidates
        catalogUpdatedAt = Date()
        return candidates
    }

    func resolve(
        records: [MenuBarOrganizerWindowRecord],
        catalog: [MenuBarItemSourceCandidate]
    ) -> [CGWindowID: MenuBarItemSourceIdentity] {
        let liveWindowIDs = Set(records.map(\.windowID))
        cache = cache.filter { liveWindowIDs.contains($0.key) }

        var result = cache

        // Priority 1 — direct window-ID match (most reliable).
        var windowIDResolved = Set<CGWindowID>()
        for candidate in catalog {
            guard let wid = candidate.windowID,
                  liveWindowIDs.contains(wid),
                  !MenuBarOrganizerSupport.isOrganizerInternalSource(candidate.source)
            else { continue }
            let existing = result[wid]
            if let existing,
               existing.bundleIdentifier != MenuBarOrganizerSupport.controlCenterBundleIdentifier,
               candidate.source.bundleIdentifier == MenuBarOrganizerSupport.controlCenterBundleIdentifier {
                continue
            }
            result[wid] = candidate.source
            cache[wid] = candidate.source
            windowIDResolved.insert(wid)
        }

        // Priority 2 — frame-based matching for records not yet resolved by window ID.
        let needsFrameMatch = records.filter { !windowIDResolved.contains($0.windowID) }
        let matches = Self.match(records: needsFrameMatch, catalog: catalog)
        for (windowID, source) in matches {
            result[windowID] = source
            cache[windowID] = source
            windowIDResolved.insert(windowID)
        }

        // Priority 3 — owner-bundle fallback for records not yet matched via AX.
        for record in records
        where !windowIDResolved.contains(record.windowID) {
            let bundleID = record.ownerBundleIdentifier.isEmpty
                ? "pid:\(record.ownerPID)"
                : record.ownerBundleIdentifier
            let source = MenuBarItemSourceIdentity(
                pid: record.ownerPID,
                bundleIdentifier: bundleID,
                name: record.ownerName.isEmpty ? bundleID : record.ownerName,
                axIdentifier: nil,
                axTitle: record.title.isEmpty ? nil : record.title)
            result[record.windowID] = source
            cache[record.windowID] = source
        }
        return result
    }

    func invalidate() {
        catalogTask?.cancel()
        catalogTask = nil
        catalogCache.removeAll()
        catalogUpdatedAt = nil
        cache.removeAll()
    }

    private func runningApplications() async -> [ApplicationRecord] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationRecord? in
                guard !app.isTerminated else { return nil }
                let bundleID = app.bundleIdentifier ?? ""
                // Exclude Control Center from AXExtrasMenuBar scanning so its internal
                // sub-controls (which are not standalone status bar icons) do not pollute the catalog.
                guard bundleID != MenuBarOrganizerSupport.controlCenterBundleIdentifier else { return nil }
                return ApplicationRecord(
                    pid: app.processIdentifier,
                    bundleIdentifier: bundleID.isEmpty
                        ? "pid:\(app.processIdentifier)"
                        : bundleID,
                    name: app.localizedName ?? bundleID)
            }
        }
    }

    private static func match(
        records: [MenuBarOrganizerWindowRecord],
        catalog: [MenuBarItemSourceCandidate]
    ) -> [CGWindowID: MenuBarItemSourceIdentity] {
        struct Candidate {
            let windowID: CGWindowID
            let source: MenuBarItemSourceIdentity
            let score: CGFloat
            let sourceSlot: String
            let usesOwnerFallback: Bool
        }

        var candidates: [Candidate] = []
        for record in records {
            guard !Task.isCancelled else { return [:] }
            for axItem in catalog {
                // A generic hosted slot can overlap Control Center's own AX
                // child exactly. That match identifies the host, not the app
                // that supplied the item, and must remain provisional.
                if MenuBarOrganizerSupport.isGenericControlCenterHostedTitle(record.title),
                   axItem.source.bundleIdentifier
                    == MenuBarOrganizerSupport.controlCenterBundleIdentifier {
                    continue
                }
                guard let score = MenuBarOrganizerSupport.frameMatchScore(
                    record.frame, axItem.frame)
                else { continue }
                candidates.append(Candidate(
                    windowID: record.windowID,
                    source: axItem.source,
                    score: score,
                    sourceSlot: axItem.slotKey,
                    usesOwnerFallback:
                        axItem.source.bundleIdentifier
                            == MenuBarOrganizerSupport.controlCenterBundleIdentifier))
            }
        }

        var usedWindows = Set<CGWindowID>()
        var usedSources = Set<String>()
        var result: [CGWindowID: MenuBarItemSourceIdentity] = [:]
        for candidate in candidates.sorted(by: {
            if $0.score != $1.score { return $0.score < $1.score }
            return !$0.usesOwnerFallback && $1.usesOwnerFallback
        }) {
            guard !usedWindows.contains(candidate.windowID),
                  !usedSources.contains(candidate.sourceSlot)
            else { continue }
            usedWindows.insert(candidate.windowID)
            usedSources.insert(candidate.sourceSlot)
            result[candidate.windowID] = candidate.source
        }
        return result
    }

    private static func scanExtrasMenuBar(_ app: ApplicationRecord) -> [MenuBarItemSourceCandidate] {
        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard let extras: AXUIElement = attribute("AXExtrasMenuBar", from: application),
              let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: extras)
        else { return [] }

        return children.compactMap { child in
            guard let frame = frame(of: child) else { return nil }
            var pid = app.pid
            AXUIElementGetPid(child, &pid)
            let source = MenuBarItemSourceIdentity(
                pid: pid,
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                axIdentifier: attribute(kAXIdentifierAttribute, from: child),
                axTitle: attribute(kAXTitleAttribute, from: child))
            // Attempt direct window-ID resolution. Fallback to frame matching
            // when the private symbol is unavailable or the element has no
            // backing CoreGraphics window yet (e.g. not yet on screen).
            var wid: CGWindowID = 0
            let resolvedWindowID: CGWindowID? = _axGetWindow.flatMap { fn in
                fn(child, &wid) == .success && wid != 0 ? wid : nil
            }
            return MenuBarItemSourceCandidate(source: source,
                                              frame: frame,
                                              windowID: resolvedWindowID)
        }
    }

    private static func attribute<T>(_ name: String,
                                     from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return nil }
        return value as? T
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let value: AXValue = attribute("AXFrame", from: element),
              AXValueGetType(value) == .cgRect
        else { return nil }
        var frame = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &frame),
              frame.width > 0,
              frame.height > 0
        else { return nil }
        return frame
    }
}
