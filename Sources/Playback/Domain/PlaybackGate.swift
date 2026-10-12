import Foundation

// MARK: - Playback gate
// Combines every deliberate reason not to play into one Playback state, so the player's pause/resume/tear-down and
// Recovery's "intends to play" come from a single tested decision rather than scattered flags.

/// A deliberate reason to stop or start playing.
public enum PlaybackInput: Equatable, Sendable {
    case lowPower(Bool)
    case screensAsleep(Bool)
    case allWindowsOccluded(Bool)
}

/// What the Live wallpaper is doing on purpose (see CONTEXT.md). Recovery is separate: it is what happens when
/// playback fails against this intent.
public enum PlaybackState: Equatable, Sendable {
    case playing
    /// Nobody can see it: every window is covered or the screens are asleep.
    case paused
    /// Low Power Mode: no player, only the Poster.
    case posterOnly
}

/// What the player must do when the Playback state changes.
public enum PlaybackGateAction: Equatable, Sendable {
    case none
    case pause
    case resume
    /// Drop the player so only the Poster shows (Low Power Mode).
    case tearDown
    /// Build a player again after a tear-down; it plays only if the Playback state is `playing`.
    case rebuild
}

/// The Recovery progress a Low Power Mode change can override; the service applies the returned copy.
struct RecoveryProgress: Equatable {
    var isRebuildPending = false
    var isRestingWithoutVideo = false
    /// The backoff is exhausted: only wake, unlock or a folder change retries a broken file.
    var isBackoffExhausted = false
}

struct PlaybackDecision: Equatable {
    let action: PlaybackGateAction
    let recovery: RecoveryProgress
}

struct PlaybackGate {
    private(set) var isLowPower = false
    private(set) var areScreensAsleep = false
    private(set) var areAllWindowsOccluded = false

    var state: PlaybackState {
        if isLowPower { return .posterOnly }
        return areScreensAsleep || areAllWindowsOccluded ? .paused : .playing
    }

    /// What Recovery treats as "should be advancing": false in Low Power Mode, while covered and while asleep.
    var isIntendingToPlay: Bool { state == .playing }
    var isPowerSaving: Bool { state == .posterOnly }

    /// Applies an input and returns what the player must do, with the Recovery progress that follows. Entering
    /// Low Power Mode drops a pending rebuild and a no-video rest, because leaving it rebuilds (re-picking the
    /// video) anyway; an exhausted backoff survives, so leaving does not retry a broken file before wake,
    /// unlock or a folder change.
    mutating func apply(_ input: PlaybackInput, recovery: RecoveryProgress) -> PlaybackDecision {
        let before = state
        switch input {
        case .lowPower(let isOn): isLowPower = isOn
        case .screensAsleep(let isAsleep): areScreensAsleep = isAsleep
        case .allWindowsOccluded(let isOccluded): areAllWindowsOccluded = isOccluded
        }
        let after = state
        switch (before, after) {
        case _ where before == after:
            return PlaybackDecision(action: .none, recovery: recovery)
        case (_, .posterOnly):
            let cleared = RecoveryProgress(isBackoffExhausted: recovery.isBackoffExhausted)
            return PlaybackDecision(action: .tearDown, recovery: cleared)
        case (.posterOnly, _):
            return PlaybackDecision(action: recovery.isBackoffExhausted ? .none : .rebuild, recovery: recovery)
        case (.playing, .paused):
            return PlaybackDecision(action: .pause, recovery: recovery)
        default:
            return PlaybackDecision(action: .resume, recovery: recovery)
        }
    }
}
