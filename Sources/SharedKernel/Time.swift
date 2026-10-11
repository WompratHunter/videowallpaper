import Foundation

// MARK: - Time
// The time values ports hand to contexts. Uptime orders events and measures Dwell, Recovery and fades: it never jumps
// with the wall clock and stops while the Mac sleeps. Wall-clock time (`Date`) is only for the sun (Daylight) and the
// log.

/// Seconds since boot.
public typealias Uptime = TimeInterval
