import Foundation

// MARK: - Playback gate
// Combines every deliberate reason not to play into one state, so the player's pause/resume/tear-down and
// Recovery's "intends to play" come from a single tested decision rather than scattered flags.

package enum PlaybackGateEvent: Equatable {
    case lowPower(Bool)
    case screensAsleep(Bool)
    case allWindowsOccluded(Bool)
}

package enum PlaybackGateAction: Equatable {
    case none
    case pause
    case resume
    /// Drop the player so only the Poster shows (Low Power Mode).
    case tearDown
    /// Build a player again after a tear-down; it plays only if the gate's mode is `playing`.
    case rebuild
}

/// The Recovery state a Low Power Mode change can override; the app applies the returned copy.
package struct RecoveryState: Equatable {
    package var isRebuildPending = false
    package var isRestingWithoutVideo = false
    /// The backoff is exhausted: only wake, unlock or a folder change retries a broken file.
    package var isBackoffExhausted = false

    package init(
        isRebuildPending: Bool = false, isRestingWithoutVideo: Bool = false, isBackoffExhausted: Bool = false
    ) {
        self.isRebuildPending = isRebuildPending
        self.isRestingWithoutVideo = isRestingWithoutVideo
        self.isBackoffExhausted = isBackoffExhausted
    }
}

package struct PlaybackDecision: Equatable {
    package let action: PlaybackGateAction
    package let recovery: RecoveryState
}

package struct PlaybackGate {
    package enum Mode: Equatable {
        case playing
        case paused
        case posterOnly
    }

    package private(set) var isLowPower = false
    package private(set) var areScreensAsleep = false
    package private(set) var areAllWindowsOccluded = false

    package init() {}

    package var mode: Mode {
        if isLowPower { return .posterOnly }
        return areScreensAsleep || areAllWindowsOccluded ? .paused : .playing
    }

    /// What Recovery treats as "should be advancing": false in Low Power Mode, while covered and while asleep.
    package var isIntendingToPlay: Bool { mode == .playing }
    package var isPowerSaving: Bool { mode == .posterOnly }

    /// Applies an event and returns what the player must do, with the Recovery state that follows. Entering
    /// Low Power Mode drops a pending rebuild and a no-video rest, because leaving it rebuilds (re-picking the
    /// video) anyway; an exhausted backoff survives, so leaving does not retry a broken file before wake,
    /// unlock or a folder change.
    package mutating func apply(_ event: PlaybackGateEvent, recovery: RecoveryState) -> PlaybackDecision {
        let before = mode
        switch event {
        case .lowPower(let isOn): isLowPower = isOn
        case .screensAsleep(let isAsleep): areScreensAsleep = isAsleep
        case .allWindowsOccluded(let isOccluded): areAllWindowsOccluded = isOccluded
        }
        let after = mode
        switch (before, after) {
        case _ where before == after:
            return PlaybackDecision(action: .none, recovery: recovery)
        case (_, .posterOnly):
            let cleared = RecoveryState(isBackoffExhausted: recovery.isBackoffExhausted)
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
