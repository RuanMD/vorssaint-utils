// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Menu-bar-specific facade over the shared WindowServer bridge. Keeping this
/// small instance API makes the provider easy to exercise while all private
/// symbols and the cached connection are owned by `SpaceWindowBridge`.
final class MenuBarWindowServerBridge: @unchecked Sendable {
    static let shared = MenuBarWindowServerBridge()

    var hasPrivateWindowList: Bool {
        SpaceWindowBridge.canListMenuBarWindows
    }

    var hasWindowFrame: Bool {
        SpaceWindowBridge.canResolveWindowFrames
    }

    private init() {}

    func menuBarWindowIDs() -> [CGWindowID]? {
        SpaceWindowBridge.menuBarWindowIDs()
    }

    func frame(for windowID: CGWindowID) -> CGRect? {
        SpaceWindowBridge.frame(of: windowID)
    }

    func level(for windowID: CGWindowID) -> CGWindowLevel? {
        SpaceWindowBridge.level(of: windowID)
    }
}
