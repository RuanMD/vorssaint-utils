// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

@MainActor
final class MenuBarOrganizerPanelController {
    enum Kind { case search, secondary }

    private let kind: Kind
    private weak var service: MenuBarOrganizerService?
    private var panel: NSPanel?

    init(kind: Kind, service: MenuBarOrganizerService) {
        self.kind = kind
        self.service = service
    }

    var isVisible: Bool { panel?.isVisible == true }

    func show(anchor: CGRect? = nil) {
        guard let service else { return }
        let content: AnyView
        let size: CGSize
        switch kind {
        case .search:
            content = AnyView(MenuBarOrganizerSearchView(service: service))
            size = CGSize(width: 470, height: 420)
        case .secondary:
            content = AnyView(MenuBarOrganizerSecondaryBarView(service: service))
            let itemCount = max(service.items.filter { $0.section != .visible }.count, 1)
            size = CGSize(width: min(max(CGFloat(itemCount) * 54 + 32, 260), 720), height: 92)
        }

        let panel = self.panel ?? makePanel(content: content, size: size)
        panel.contentViewController = NSHostingController(rootView: content)
        panel.setContentSize(size)
        position(panel, anchor: anchor)
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel(content: AnyView, size: CGSize) -> NSPanel {
        let style: NSWindow.StyleMask = kind == .search
            ? [.titled, .fullSizeContentView]
            : [.titled, .fullSizeContentView, .nonactivatingPanel]
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: style,
                            backing: .buffered,
                            defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = kind == .search
        panel.hidesOnDeactivate = kind == .secondary
        panel.contentViewController = NSHostingController(rootView: content)
        return panel
    }

    private func position(_ panel: NSPanel, anchor: CGRect?) {
        if let anchor, kind == .secondary {
            let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? .zero
            var origin = CGPoint(x: anchor.midX - panel.frame.width / 2,
                                 y: anchor.minY - panel.frame.height - 6)
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }
    }
}

private struct MenuBarOrganizerSearchView: View {
    @ObservedObject var service: MenuBarOrganizerService
    @State private var query = ""

    private var matches: [ManagedMenuBarItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return service.items
        }
        return service.items.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search menu bar items", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(14)
            Divider()
            if matches.isEmpty {
                ContentUnavailableView("No menu bar items",
                                       systemImage: "menubar.rectangle",
                                       description: Text("Try another search."))
            } else {
                List(matches) { item in
                    Button {
                        service.activate(itemID: item.id)
                    } label: {
                        MenuBarOrganizerItemLabel(item: item, showsSection: true)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .onAppear { service.refresh() }
    }
}

private struct MenuBarOrganizerSecondaryBarView: View {
    @ObservedObject var service: MenuBarOrganizerService

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(service.items.filter { $0.section != .visible }) { item in
                    Button {
                        service.activate(itemID: item.id)
                    } label: {
                        VStack(spacing: 4) {
                            MenuBarOrganizerItemIcon(item: item, size: 24)
                            Text(item.ownerName.isEmpty ? item.title : item.ownerName)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(maxWidth: 70)
                        }
                        .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help(item.displayName)
                }
            }
            .padding(12)
        }
        .background(.ultraThinMaterial)
    }
}

struct MenuBarOrganizerItemLabel: View {
    let item: ManagedMenuBarItem
    var showsSection = false

    var body: some View {
        HStack(spacing: 10) {
            MenuBarOrganizerItemIcon(item: item, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).lineLimit(1)
                if showsSection {
                    Text(item.section.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !item.isMovable {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MenuBarOrganizerItemIcon: View {
    let item: ManagedMenuBarItem
    let size: CGFloat

    var body: some View {
        Group {
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: item.bundleIdentifier.hasPrefix("com.apple.")
                      ? "switch.2" : "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
