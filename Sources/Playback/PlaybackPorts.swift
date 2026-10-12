import Foundation
import SharedKernel

// MARK: - Playback ports
// Everything Playback needs from the system, so the service can be tested end to end with fakes. Today's adapters:
// `SharedPlayer` (AVFoundation queue players and layers) and `WallpaperWindows` (AppKit desktop-level windows) here,
// `DispatchPlaybackClock` here, and Platform's `ProcessInfoPower` and `WorkspaceScreenSession`.

/// The shared player: one current looping player shown on every window above the Poster, and during a crossfade an
/// incoming one fading in above it. Decisions are the service's; this only builds, plays and reports.
@MainActor
public protocol PlayerPort: AnyObject {
    /// What the player reports, on the main queue.
    var onSignal: (PlayerSignal) -> Void { get set }
    var hasCurrent: Bool { get }
    /// The current player's time in seconds; nil without a player or before it has a time.
    var position: Double? { get }
    var hasFailed: Bool { get }
    /// The current player's state for the log; `.noPlayer` without one.
    func stateReport(timeAdvanced: Bool?) -> PlayerStateReport

    /// Builds a muted looping player for `video` on every window's video layer, paused until `play()`.
    func loadCurrent(_ video: URL)
    /// Drops the current player: the Poster shows.
    func releaseCurrent()
    func play()
    func pause()
    /// Seeks the current player; `then` runs on the main queue if it is still the current one.
    func seek(to seconds: Double, then: @escaping () -> Void)

    /// Builds and plays the incoming player for `video`, hidden above the current one; it reports
    /// `.incomingReady(id:)` once every window can draw it, or `.incomingFailed(id:)`.
    func loadIncoming(_ video: URL, id: Int)
    func fadeInIncoming(duration: TimeInterval)
    /// The incoming player replaces the current one, which is released.
    func promoteIncoming()
    func dropIncoming()

    /// The still under every window's video, shown whenever there is no player.
    func setPoster(_ poster: PosterImage)
}

public enum PlayerSignal: Equatable {
    /// The current item is ready to play.
    case ready
    case failed(PlayerFailure)
    case incomingReady(id: Int)
    case incomingFailed(id: Int)
}

public enum PlayerFailure: Equatable {
    case item
    case looper
    /// The item failed to play to its end, with the error's description.
    case playToEnd(error: String?)
}

/// One desktop-level window per screen, hosting the player's layers.
@MainActor
public protocol WallpaperWindowsPort: AnyObject {
    /// What changed and whether every window is now covered by opaque windows, on each build and occlusion change.
    var onOcclusionChange: (OcclusionChange, Bool) -> Void { get set }
    /// One window per connected screen.
    func rebuild()
    /// The window level and order can be lost across wake and Space switches.
    func reassert()
}

/// Low Power Mode as the system reports it.
@MainActor
public protocol PowerPort: AnyObject {
    var isLowPowerModeEnabled: Bool { get }
    /// Called on the main queue when Low Power Mode turns on or off.
    var onChange: () -> Void { get set }
}

/// The screen and session notifications Playback (and, through the coordinator, Presence, Rotation and Daylight)
/// hears.
@MainActor
public protocol ScreenSessionPort: AnyObject {
    /// Called on the main queue.
    var onEvent: (ScreenSessionEvent) -> Void { get set }
}

public enum ScreenSessionEvent: Equatable, Sendable {
    case screensDidSleep
    case screensDidWake
    case systemDidWake
    case sessionDidBecomeActive
    case sessionDidResignActive
    /// Screens were added, removed or rearranged.
    case screenParametersChanged
}

/// Uptime and delayed work: Recovery's backoff, the wake-time sample and a fade's end.
@MainActor
public protocol PlaybackClock: AnyObject {
    var uptime: Uptime { get }
    /// Runs `work` on the main queue after `delay` seconds, unless cancelled first.
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> ScheduledWork
}

public protocol ScheduledWork: AnyObject {
    func cancel()
}
