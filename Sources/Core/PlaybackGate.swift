import Foundation

// MARK: - Playback gate
// Combines every deliberate reason not to play into one state, so the player's pause/resume/tear-down and
// Recovery's "intends to play" come from a single tested decision rather than scattered flags.

enum PlaybackEvent: Equatable {
    case lowPower(Bool)
    case screensAsleep(Bool)
    case allWindowsOccluded(Bool)
}

enum PlaybackGateAction: Equatable {
    case none
    case pause
    case resume
    /// Drop the player so only the Poster shows (Low Power Mode).
    case tearDown
    /// Build a player again after a tear-down; it plays only if the gate's mode is `playing`.
    case rebuild
}

struct PlaybackGate {
    enum Mode: Equatable {
        case playing
        case paused
        case posterOnly
    }

    private(set) var isLowPower = false
    private(set) var areScreensAsleep = false
    private(set) var areAllWindowsOccluded = false

    var mode: Mode {
        if isLowPower { return .posterOnly }
        return areScreensAsleep || areAllWindowsOccluded ? .paused : .playing
    }

    /// What Recovery treats as "should be advancing": false in Low Power Mode, while covered and while asleep.
    var isIntendingToPlay: Bool { mode == .playing }
    var isPowerSaving: Bool { mode == .posterOnly }

    /// Applies an event and returns what the player must do. `isRecoveryResting` is whether the backoff is
    /// exhausted: leaving Low Power Mode must not retry a broken file before wake, unlock or a folder change.
    mutating func apply(_ event: PlaybackEvent, isRecoveryResting: Bool) -> PlaybackGateAction {
        let before = mode
        switch event {
        case .lowPower(let isOn): isLowPower = isOn
        case .screensAsleep(let isAsleep): areScreensAsleep = isAsleep
        case .allWindowsOccluded(let isOccluded): areAllWindowsOccluded = isOccluded
        }
        let after = mode
        switch (before, after) {
        case _ where before == after: return .none
        case (_, .posterOnly): return .tearDown
        case (.posterOnly, _): return isRecoveryResting ? .none : .rebuild
        case (.playing, .paused): return .pause
        default: return .resume
        }
    }
}

/// Each window's "visible" occlusion flag. Translucent windows (e.g. Ghostty) don't clear the flag, so only
/// opaque coverage of every display counts. No windows at all is not "covered".
func areAllWindowsOccluded(visibility: [Bool]) -> Bool {
    !visibility.isEmpty && !visibility.contains(true)
}
