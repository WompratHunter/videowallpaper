import Foundation
import SharedKernel

// MARK: - Rotation inputs
// What a Rotation decision reads, pulled at decision time. The coordinator fills these from the other contexts, so
// the Rotation never hears of them directly (ADR 0002).

public struct RotationInputs {
    public var uptime: () -> Uptime = { ProcessInfo.processInfo.systemUptime }
    public var eligibleVideos: () -> [EligibleVideo] = { [] }
    public var presence: () -> Presence = { .visible }
    /// Samples window coverage for Veiled; asked only while a switch point is near.
    public var checkVeil: () -> Presence = { .visible }
    public var isLowPowerMode: () -> Bool = { false }
    /// The raw `Mode` setting, read at every decision so a change applies without a restart.
    public var modeSetting: () -> String? = { nil }
    /// Daylight (the Target brightness) and where it came from, for the log. Asked only while `dynamic` aims at it,
    /// so Location Services is asked for only then.
    public var daylight: () -> (level: Double, source: String) = { (0, "none") }

    public init() {}
}

// MARK: - Auto-appearance port

/// Whether the system appearance switches automatically, which makes `dynamic` the default Mode. The flag is
/// undocumented, so an adapter that can't read it answers false and the default Mode falls back to `all`.
public protocol AutoAppearancePort: AnyObject {
    var isAutoAppearance: Bool { get }
}
