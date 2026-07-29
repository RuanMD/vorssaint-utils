// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Decides when a hot CPU reading deserves a notification.
///
/// The temperature is the hottest core sensor at that instant, and those
/// sensors move by degrees from one reading to the next, so a single reading
/// over the limit proves nothing: a short burst can push one core past the
/// limit and be gone again before the panel is even open. The alert waits for
/// the temperature to hold across separate readings, for the same window the
/// CPU usage alert already uses.
struct TemperatureAlertGate {
    /// How long the temperature has to hold, matching the CPU usage alert.
    static let sustainedSeconds: TimeInterval = 12

    private var hotSince: TimeInterval?
    private var lastReadingAt: TimeInterval?

    /// `readAt` is when the sensor was actually read. The monitor keeps
    /// serving the last reading in between reads, and counting those repeats
    /// would let one burst age into an alert on its own. It comes from the
    /// system uptime clock, which stops while the Mac sleeps, so a sleep in
    /// the middle cannot pass for a long hot stretch either.
    mutating func shouldAlert(temperature: Double?,
                              threshold: Double,
                              readAt: TimeInterval?) -> Bool {
        guard let temperature, let readAt, temperature >= threshold else {
            reset()
            return false
        }
        guard readAt != lastReadingAt else { return false }
        lastReadingAt = readAt
        guard let since = hotSince else {
            hotSince = readAt
            return false
        }
        return readAt - since >= Self.sustainedSeconds
    }

    mutating func reset() {
        hotSince = nil
        lastReadingAt = nil
    }
}
