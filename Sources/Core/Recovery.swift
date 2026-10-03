import Foundation

// MARK: - Recovery decision
// Decides from plain samples whether the shared player must be rebuilt. Playback time is compared between
// health ticks because timeControlStatus can report "playing" for a player that has silently died.

enum RecoveryCause: String {
    case failed
    case stuck
    case notPlayingOnWake = "not-playing-on-wake"
    case fileMissing = "file-missing"
    case retryAfterRest = "retry-after-rest"
}

/// Where a rebuilt player starts: the saved position for the same video, the beginning for a replacement.
func resumePosition(rebuilding target: URL, current: URL?, saved: Double) -> Double {
    target == current ? saved : 0
}

struct HealthSample {
    /// Monotonic clock reading, in seconds.
    let now: TimeInterval
    let playbackSeconds: Double?
    /// False while playback is paused on purpose (e.g. screens asleep), when frozen time is expected.
    let isIntendingToPlay: Bool
    let hasFailed: Bool
}

struct RecoveryMonitor {
    static let stuckTicks = 2
    static let gracePeriod: TimeInterval = 15

    private var hasBaseline = false
    private var lastSeconds: Double?
    private var stalledTicks = 0
    private var graceStart: TimeInterval?

    mutating func tick(_ sample: HealthSample) -> RecoveryCause? {
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

    mutating func noteRebuild(at now: TimeInterval) {
        graceStart = now
        restartBaseline()
    }

    /// Resuming after an intentional pause gets the same grace: a healthy player can take seconds to restart.
    mutating func noteResume(at now: TimeInterval) {
        noteRebuild(at: now)
    }

    /// On wake or unlock a healthy player is left alone; only one that is not actually playing is rebuilt.
    func verdictAfterWake(
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

struct RecoveryBackoff {
    enum ResetEvent: String {
        case wake
        case unlock
        case folderChange = "folder-change"
    }

    static let delays: [TimeInterval] = [10, 60, 300]

    private var attempts = 0

    /// True once every scheduled attempt has been used: the Live wallpaper rests on the Poster.
    var isResting: Bool { attempts > Self.delays.count }

    /// Delay before the next rebuild, or nil when the schedule is exhausted and the Poster should stay.
    mutating func nextDelay() -> TimeInterval? {
        attempts = min(attempts + 1, Self.delays.count + 1)
        return isResting ? nil : Self.delays[attempts - 1]
    }

    mutating func reset(on event: ResetEvent) {
        attempts = 0
    }
}
