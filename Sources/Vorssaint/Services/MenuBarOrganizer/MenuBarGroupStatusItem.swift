// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

@MainActor
final class MenuBarGroupStatusItem: NSObject {
    let slot: MenuBarOrganizerGroupSlot
    private(set) var statusItem: NSStatusItem
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    private let autosaveName: String

    var windowID: CGWindowID? {
        statusItem.button?.window.map { CGWindowID($0.windowNumber) }
    }

    var frame: CGRect? { statusItem.button?.window?.frame }

    init(slot: MenuBarOrganizerGroupSlot) {
        self.slot = slot
        autosaveName = "Vorssaint.MenuBarOrganizer.Group.\(slot.rawValue)"
        let defaults = UserDefaults.standard
        let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
        if defaults.object(forKey: positionKey) == nil {
            let index = MenuBarOrganizerGroupSlot.allCases.firstIndex(of: slot) ?? 0
            let position = 3 + Double(index)
            defaults.set(position, forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.autosaveName = autosaveName
        statusItem.behavior = []
        statusItem.isVisible = true
        configureButton()
    }

    deinit {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        let cached = UserDefaults.standard.object(forKey: key)
        NSStatusBar.system.removeStatusItem(statusItem)
        if let cached { UserDefaults.standard.set(cached, forKey: key) }
    }

    func update(title: String, itemCount: Int, isVisible: Bool) {
        statusItem.isVisible = isVisible
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.toolTip = "\(title) (\(itemCount))"
    }

    func removePreservingPosition() {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        let cached = UserDefaults.standard.object(forKey: key)
        statusItem.isVisible = false
        if let cached { UserDefaults.standard.set(cached, forKey: key) }
    }

    private var symbolName: String {
        switch slot {
        case .cloud: return "icloud"
        case .audio: return "speaker.wave.2"
        case .work: return "briefcase"
        case .custom: return "folder"
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            onRightClick?()
        } else {
            onLeftClick?()
        }
    }
}
