import Core
import Foundation
import Rotation
import SharedKernel

// MARK: - Rotation service
// The Rotation as the coordinator sees it, with today's `RotationScheduler` (Sources/App) as its adapter. A seam for
// the move only: ticket 08 moves the scheduler into the Rotation context, which then needs no protocol (it has no OS
// adapters but the auto-appearance flag).

/// What a Rotation decision reads, pulled at decision time. The coordinator fills these from the other contexts.
package struct RotationInputs {
    package var uptime: () -> Uptime = { ProcessInfo.processInfo.systemUptime }
    package var eligibleVideos: () -> [EligibleVideo] = { [] }
    package var presence: () -> Presence = { .visible }
    /// Samples window coverage for Veiled; asked only while a switch point is near.
    package var checkVeil: () -> Presence = { .visible }
    package var isPowerSaving: () -> Bool = { false }
    /// The raw `Mode` setting, read at every decision so a change applies without a restart.
    package var modeSetting: () -> String? = { nil }
    /// Daylight (the Target brightness) and where it came from, for the log. Asked only while `dynamic` aims at it,
    /// so Location Services is asked for only then.
    package var daylight: () -> (level: Double, source: String) = { (0, "none") }

    package init() {}
}

package protocol RotationService: AnyObject {
    /// The Rotation's events, on the main queue.
    var onEvent: (RotationEvent) -> Void { get set }
    /// The Current video: what a rebuild or a folder change should play.
    var video: URL? { get }
    var slice: RotationSlice { get }

    func connect(_ inputs: RotationInputs)
    /// Picks the first video, for the player's start to build. Once, at launch: `present` (the folder's videos then)
    /// join the Rotation as their Analysis finishes, without counting as newly added.
    func start(present: Set<String>)
    /// On the tick and on a Presence change: decides, and returns the video to switch to if the moment allows.
    func evaluate(cause: String) -> (video: URL, fade: TimeInterval)?
    /// On a folder change or a rebuild: decides without switching, since the caller hands `video` to the player.
    func refresh(cause: String) -> RotationSwitch?
    /// Lock, screen sleep and session changes pause and resume Dwell.
    func apply(_ event: AwayFromDesk)
}
