// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// A hand-rolled stand-in for `NSView.toolTip`, used only for Shelf tiles.
///
/// The Shelf panel is a `.nonactivatingPanel` so dragging a file into it
/// never steals focus from whatever app the file came from. AppKit's own
/// tooltip manager, it turns out, only displays over a key window (or an
/// active app) - it never has a reason to become either before the user
/// clicks something, so native tooltips silently never appeared. This
/// panel orders itself front without ever calling `makeKey()` or
/// activating the app, so it shows on a plain hover with none of that
/// side effect.
final class ShelfTooltipPopover {
    static let shared = ShelfTooltipPopover()

    private static let showDelay: TimeInterval = 1.0
    private static let margin: CGFloat = 6
    private static let gap: CGFloat = 6
    private static let maxWidth: CGFloat = 280

    private var panel: NSPanel?
    private var label: NSTextField?
    private var pendingWork: DispatchWorkItem?

    private init() {}

    /// `owner` anchors both the eventual position and a liveness check: the
    /// delay means real time passes between scheduling and showing, during
    /// which the Shelf can close without ever delivering `mouseExited` to
    /// `owner` (observed happening when the mouse leaves the panel and the
    /// panel hides in the same stroke) - so this re-checks `owner.window`
    /// is still visible right before showing, rather than trusting that a
    /// cancellation would have arrived by then.
    func scheduleShow(text: String, for owner: NSView) {
        cancelPending()
        let work = DispatchWorkItem { [weak self, weak owner] in
            guard let owner, owner.window?.isVisible == true else { return }
            self?.show(text: text, near: owner)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
    }

    func hide() {
        cancelPending()
        panel?.orderOut(nil)
    }

    private func cancelPending() {
        pendingWork?.cancel()
        pendingWork = nil
    }

    private func show(text: String, near owner: NSView) {
        guard let ownerWindow = owner.window else { return }
        let panel = ensurePanel()
        guard let label else { return }
        label.stringValue = text
        // preferredMaxLayoutWidth, not a plain sizeToFit(), so long content
        // (an untruncated filename, a full URL, up to 500 characters of
        // pasted text) wraps within a fixed width instead of measuring as
        // one unbounded line and running the popup off the edge of the
        // screen.
        label.preferredMaxLayoutWidth = Self.maxWidth
        let natural = label.intrinsicContentSize
        let textWidth = min(natural.width, Self.maxWidth)
        label.frame = NSRect(x: Self.margin, y: Self.margin, width: textWidth, height: natural.height)
        let size = NSSize(width: textWidth + Self.margin * 2, height: natural.height + Self.margin * 2)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)

        // Anchored to the tile's own frame, not the live cursor position:
        // the cursor may have moved anywhere in the time since the hover
        // that scheduled this (including onto a different app entirely).
        let ownerScreenFrame = ownerWindow.convertToScreen(owner.convert(owner.bounds, to: nil))
        let screen = ownerWindow.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        var origin = NSPoint(x: ownerScreenFrame.minX, y: ownerScreenFrame.minY - Self.gap - size.height)
        if origin.y < screen.minY {
            // Not enough room below the tile - flip above it instead of
            // letting the clamp below just pin it in place, which would
            // otherwise overlap the bottom of the tile it's describing.
            origin.y = ownerScreenFrame.maxY + Self.gap
        }
        origin.x = min(max(screen.minX, origin.x), screen.maxX - size.width)
        origin.y = min(max(screen.minY, origin.y), screen.maxY - size.height)

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFront(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let effect = NSVisualEffectView()
        effect.material = .toolTip
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 5
        effect.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        // Wraps rather than truncates: the whole point of this tooltip is
        // to show what the tile itself couldn't fit. Content is already
        // capped upstream (500 characters for pasted text), so unlimited
        // lines here just means "wrap that, don't cut it again."
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0

        effect.addSubview(label)
        panel.contentView = effect
        self.panel = panel
        self.label = label
        return panel
    }
}
