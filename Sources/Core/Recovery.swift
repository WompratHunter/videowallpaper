import Foundation

// MARK: - Recovery decision
// Decides from plain samples whether the shared player must be rebuilt. Playback time is compared between
// health ticks because timeControlStatus can report "playing" for a player that has silently died.

package enum RecoveryCause: String {
    case failed
    case stuck
    case notPlayingOnWake = "not-playing-on-wake"
    case fileMissing = "file-missing"
    case retryAfterRest = "retry-after-rest"
    case videoAvailable = "video-available"
}

package enum RebuildPlan: Equatable {
    case play(URL, at: Double)
    /// No eligible video in the folder: rest on the Poster. Not a failure, so the backoff does not advance.
    case restNoVideo
    /// Low Power Mode: build nothing. Leaving Low Power Mode rebuilds instead.
    case holdForPower
}

/// What a rebuild does, given the Rotation's Current video asked for again at rebuild time.
/// The same video resumes at the saved position; a replacement starts from the beginning.
package func rebuildPlan(toPlay: URL?, current: URL?, saved: Double, isPowerSaving: Bool) -> RebuildPlan {
    if isPowerSaving { return .holdForPower }
    guard let toPlay else { return .restNoVideo }
    return .play(toPlay, at: toPlay == current ? saved : 0)
}

package struct HealthSample {
    /// Monotonic clock reading, in seconds.
    package let now: TimeInterval
    package let playbackSeconds: Double?
    /// False while playback is paused on purpose (e.g. screens asleep), when frozen time is expected.
    package let isIntendingToPlay: Bool
    package let hasFailed: Bool

    package init(now: TimeInterval, playbackSeconds: Double?, isIntendingToPlay: Bool, hasFailed: Bool) {
        self.now = now
        self.playbackSeconds = playbackSeconds
        self.isIntendingToPlay = isIntendingToPlay
        self.hasFailed = hasFailed
    }
}

package struct RecoveryMonitor {
    package static let stuckTicks = 2
    package static let gracePeriod: TimeInterval = 15

    private var hasBaseline = false
    private var lastSeconds: Double?
    private var stalledTicks = 0
    private var graceStart: TimeInterval?

    package init() {}

    package mutating func tick(_ sample: HealthSample) -> RecoveryCause? {
        guard sample.isIntendingToPlay else {
            restartBaseline()
            return nil
        }
        if sample.hasFailed { return .failed }
        defer {
            lastSeconds = sample.playbackSeconds
            hasBaseline = true
        }
        guard hasBaseline, !isInGrace(at: sample.now) else { return nil }
        let advanced = playbackAdvanced(from: lastSeconds, to: sample.playbackSeconds) == true
        stalledTicks = advanced ? 0 : stalledTicks + 1
        return stalledTicks >= Self.stuckTicks ? .stuck : nil
    }

    package mutating func noteRebuild(at now: TimeInterval) {
        graceStart = now
        restartBaseline()
    }

    /// Resuming after an intentional pause gets the same grace: a healthy player can take seconds to restart.
    package mutating func noteResume(at now: TimeInterval) {
        noteRebuild(at: now)
    }

    /// On wake or unlock a healthy player is left alone; only one that is not actually playing is rebuilt.
    package func verdictAfterWake(
        at now: TimeInterval, timeAdvanced: Bool?, isIntendingToPlay: Bool, hasFailed: Bool
    ) -> RecoveryCause? {
        guard isIntendingToPlay else { return nil }
        if hasFailed { return .failed }
        return timeAdvanced == true || isInGrace(at: now) ? nil : .notPlayingOnWake
    }

    private func isInGrace(at now: TimeInterval) -> Bool {
        guard let graceStart else { return false }
        return now - graceStart < Self.gracePeriod
    }

    private mutating func restartBaseline() {
        hasBaseline = false
        lastSeconds = nil
        stalledTicks = 0
    }
}

// MARK: - Recovery backoff

package struct RecoveryBackoff {
    package enum ResetEvent: String {
        case wake
        case unlock
        case folderChange = "folder-change"
    }

    package static let delays: [TimeInterval] = [10, 60, 300]

    private var attempts = 0

    package init() {}

    /// True once every scheduled attempt has been used: the Live wallpaper rests on the Poster.
    package var isResting: Bool { attempts > Self.delays.count }

    /// Delay before the next rebuild, or nil when the schedule is exhausted and the Poster should stay.
    package mutating func nextDelay() -> TimeInterval? {
        attempts = min(attempts + 1, Self.delays.count + 1)
        return isResting ? nil : Self.delays[attempts - 1]
    }

    /// Returns true when a rest on the Poster should end with a retry now. Not in Low Power Mode: no player is
    /// built there, so a retry would only spend an attempt; leaving Low Power Mode rebuilds anyway.
    @discardableResult
    package mutating func reset(on event: ResetEvent, isPowerSaving: Bool) -> Bool {
        let wasResting = isResting
        attempts = 0
        return wasResting && !isPowerSaving
    }
}
