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
        // Measured with boundingRect, not intrinsicContentSize: this field
        // has no Auto Layout constraints (plain frame positioning), and
        // preferredMaxLayoutWidth/intrinsicContentSize both silently ignore
        // that outside of an actual constraint-based layout pass - it was
        // returning single-line width regardless, chopping a wrapped
        // second line off a pile's tooltip ("6 items: 6" instead of
        // "6 items: 6 files"). boundingRect measures wrapped text directly,
        // independent of any layout system.
        let attributes: [NSAttributedString.Key: Any] = [.font: label.font as Any]
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: Self.maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes)
        let textSize = NSSize(width: ceil(bounding.width), height: ceil(bounding.height))
        label.frame = NSRect(x: Self.margin, y: Self.margin, width: textSize.width, height: textSize.height)
        let size = NSSize(width: textSize.width + Self.margin * 2, height: textSize.height + Self.margin * 2)
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
