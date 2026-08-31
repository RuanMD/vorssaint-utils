// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

@MainActor
final class MenuBarOrganizerSearchPanelController {
    private weak var service: MenuBarOrganizerService?
    private var panel: NSPanel?

    init(service: MenuBarOrganizerService) {
        self.service = service
    }

    func contains(point: CGPoint) -> Bool {
        panel?.frame.contains(point) == true
    }

    func show(anchor: CGRect?) {
        guard let service else { return }
        let panel = self.panel ?? makePanel()
        panel.contentViewController = NSHostingController(
            rootView: MenuBarOrganizerSearchView(service: service, close: { [weak self] in
                self?.close()
            }))
        position(panel, anchor: anchor)
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 380, height: 340),
                             styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = true
        return panel
    }

    private func position(_ panel: NSPanel, anchor: CGRect?) {
        let screen = anchor.flatMap { anchor in
            NSScreen.screens.first { $0.frame.intersects(anchor) }
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let origin = CGPoint(x: visible.midX - panel.frame.width / 2,
                             y: visible.midY - panel.frame.height / 2)
        panel.setFrameOrigin(origin)
    }
}

private struct MenuBarOrganizerSearchView: View {
    @ObservedObject var service: MenuBarOrganizerService
    @ObservedObject private var l10n = L10n.shared
    let close: () -> Void
    @State private var query = ""

    private var text: MenuBarOrganizerAdvancedStrings {
        FeatureStrings.menuBarOrganizerAdvanced(l10n.language)
    }

    private var results: [ManagedMenuBarItem] {
        service.searchItems(query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text.search)
                .font(.headline)
            TextField(text.search, text: $query)
                .textFieldStyle(.roundedBorder)
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Type an item name to search the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if results.isEmpty {
                Text("No matching menu bar items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(results) { item in
                            Button {
                                service.activate(itemID: item.id)
                                close()
                            } label: {
                                MenuBarOrganizerItemLabel(item: item, showsSection: true)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 380, height: 340)
    }
}
