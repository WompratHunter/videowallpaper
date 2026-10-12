import Foundation
@testable import Playback
import Testing

// MARK: - Recovery tests

private func sample(
    at now: TimeInterval, _ seconds: Double?, intending: Bool = true, failed: Bool = false
) -> HealthSample {
    HealthSample(now: now, playbackSeconds: seconds, isIntendingToPlay: intending, hasFailed: failed)
}

@Test func recoveryStuck() {
    var monitor = RecoveryMonitor()
    #expect(monitor.tick(sample(at: 100, 4.0)) == nil)
    #expect(monitor.tick(sample(at: 105, 4.0)) == nil)
    #expect(monitor.tick(sample(at: 110, 4.0)) == .stuck)

    // A single frozen tick between advancing ones is not a stall.
    var flaky = RecoveryMonitor()
    for (now, seconds) in [(0.0, 1.0), (5, 1.0), (10, 6.0), (15, 6.0), (20, 11.0)] {
        #expect(flaky.tick(sample(at: now, seconds)) == nil)
    }

    // A player with no current time (item gone) is not advancing.
    var vanished = RecoveryMonitor()
    #expect(vanished.tick(sample(at: 0, 2.0)) == nil)
    #expect(vanished.tick(sample(at: 5, nil)) == nil)
    #expect(vanished.tick(sample(at: 10, nil)) == .stuck)
}

@Test func recoveryNoIntent() {
    // Paused on purpose (screens asleep): frozen time is expected, so those ticks never count.
    var monitor = RecoveryMonitor()
    #expect(monitor.tick(sample(at: 0, 3.0)) == nil)
    #expect(monitor.tick(sample(at: 5, 3.0, intending: false)) == nil)
    #expect(monitor.tick(sample(at: 10, 3.0, intending: false)) == nil)
    #expect(monitor.tick(sample(at: 15, 3.0, intending: false, failed: true)) == nil)
    // Resuming starts a fresh baseline rather than comparing against the paused time.
    #expect(monitor.tick(sample(at: 20, 3.0)) == nil)
    #expect(monitor.tick(sample(at: 25, 8.0)) == nil)
}

@Test func recoveryFailed() {
    // A failed item is rebuilt on the first tick that sees it, without waiting for a stall.
    var monitor = RecoveryMonitor()
    #expect(monitor.tick(sample(at: 0, 2.0, failed: true)) == .failed)
    var playing = RecoveryMonitor()
    #expect(playing.tick(sample(at: 0, 2.0)) == nil)
    #expect(playing.tick(sample(at: 5, 7.0, failed: true)) == .failed)
}

@Test func recoveryGrace() {
    var monitor = RecoveryMonitor()
    monitor.noteRebuild(at: 100)
    // Loading a rebuilt item can take a while: no stall verdict within 15 s of the rebuild.
    #expect(monitor.tick(sample(at: 101, 0.0)) == nil)
    #expect(monitor.tick(sample(at: 106, 0.0)) == nil)
    #expect(monitor.tick(sample(at: 111, 0.0)) == nil)
    // After the grace window, two stalled ticks are needed again.
    #expect(monitor.tick(sample(at: 116, 0.0)) == nil)
    #expect(monitor.tick(sample(at: 121, 0.0)) == .stuck)

    // A failure is definitive, so grace does not hide it.
    var failing = RecoveryMonitor()
    failing.noteRebuild(at: 100)
    #expect(failing.tick(sample(at: 102, nil, failed: true)) == .failed)

    // A rebuild discards stalls counted against the old player.
    var stalled = RecoveryMonitor()
    #expect(stalled.tick(sample(at: 0, 5.0)) == nil)
    #expect(stalled.tick(sample(at: 5, 5.0)) == nil)
    stalled.noteRebuild(at: 6)
    #expect(stalled.tick(sample(at: 25, 5.0)) == nil)
    #expect(stalled.tick(sample(at: 30, 9.0)) == nil)
}

@Test func recoveryWake() {
    // A healthy player is never interrupted on wake or unlock.
    let fresh = RecoveryMonitor()
    #expect(fresh.verdictAfterWake(at: 0, timeAdvanced: true, isIntendingToPlay: true, hasFailed: false) == nil)
    #expect(
        fresh.verdictAfterWake(at: 0, timeAdvanced: false, isIntendingToPlay: true, hasFailed: false)
            == .notPlayingOnWake)
    #expect(
        fresh.verdictAfterWake(at: 0, timeAdvanced: nil, isIntendingToPlay: true, hasFailed: false)
            == .notPlayingOnWake)
    #expect(fresh.verdictAfterWake(at: 0, timeAdvanced: true, isIntendingToPlay: true, hasFailed: true) == .failed)
    #expect(fresh.verdictAfterWake(at: 0, timeAdvanced: nil, isIntendingToPlay: false, hasFailed: true) == nil)

    // A player rebuilt moments ago (e.g. at launch) may still be loading, so not advancing is no verdict yet.
    var monitor = RecoveryMonitor()
    monitor.noteRebuild(at: 50)
    #expect(monitor.verdictAfterWake(at: 51, timeAdvanced: false, isIntendingToPlay: true, hasFailed: false) == nil)
    #expect(monitor.verdictAfterWake(at: 51, timeAdvanced: nil, isIntendingToPlay: true, hasFailed: true) == .failed)
    #expect(
        monitor.verdictAfterWake(at: 70, timeAdvanced: false, isIntendingToPlay: true, hasFailed: false)
            == .notPlayingOnWake)
}

@Test func recoveryResumeGrace() {
    // After display sleep a healthy player can take seconds to restart, so resuming starts the same grace.
    var monitor = RecoveryMonitor()
    monitor.noteResume(at: 200)
    #expect(monitor.verdictAfterWake(at: 201, timeAdvanced: false, isIntendingToPlay: true, hasFailed: false) == nil)
    #expect(monitor.tick(sample(at: 205, 3.0)) == nil)
    #expect(monitor.tick(sample(at: 210, 3.0)) == nil)
    #expect(monitor.tick(sample(at: 220, 3.0)) == nil)
    #expect(monitor.tick(sample(at: 225, 3.0)) == .stuck)
}

@Test func recoveryRebuildPlan() {
    let rain = URL(fileURLWithPath: "/v/rain.mp4")
    let sea = URL(fileURLWithPath: "/v/sea.mp4")
    // A rebuild re-picks from the folder: the same video resumes where it stopped, a replacement starts at 0.
    #expect(rebuildPlan(toPlay: rain, current: rain, saved: 42.5, isPowerSaving: false) == .play(rain, at: 42.5))
    #expect(rebuildPlan(toPlay: sea, current: rain, saved: 42.5, isPowerSaving: false) == .play(sea, at: 0))
    #expect(rebuildPlan(toPlay: sea, current: nil, saved: 42.5, isPowerSaving: false) == .play(sea, at: 0))
    // No eligible video left: rest on the Poster rather than retrying the stale file.
    #expect(rebuildPlan(toPlay: nil, current: rain, saved: 42.5, isPowerSaving: false) == .restNoVideo)
    // A backoff timer firing in Low Power Mode builds nothing; leaving Low Power Mode rebuilds instead.
    #expect(rebuildPlan(toPlay: rain, current: rain, saved: 42.5, isPowerSaving: true) == .holdForPower)
    #expect(rebuildPlan(toPlay: nil, current: rain, saved: 42.5, isPowerSaving: true) == .holdForPower)
}

@Test func recoveryBackoff() {
    var backoff = RecoveryBackoff()
    #expect(backoff.nextDelay() == 10)
    #expect(backoff.nextDelay() == 60)
    #expect(backoff.nextDelay() == 300)
    // After three failed attempts a truly broken file rests on the Poster instead of burning CPU.
    #expect(backoff.nextDelay() == nil)
    #expect(backoff.nextDelay() == nil)
    #expect(backoff.isResting, "resting after the schedule is exhausted")

    // Wake, unlock and folder change all reset the count, so one bad night doesn't strand a good video.
    for event in [RecoveryReset.wake, .unlock, .folderChange] {
        var used = RecoveryBackoff()
        for _ in 0..<4 { _ = used.nextDelay() }
        let retries = used.reset(on: event, isPowerSaving: false)
        #expect(retries, "a rest ends with a retry on \(event)")
        #expect(!used.isResting, "not resting after reset on \(event)")
        #expect(used.nextDelay() == 10)
    }

    // Nothing to retry when not resting.
    var fresh = RecoveryBackoff()
    _ = fresh.nextDelay()
    let freshRetries = fresh.reset(on: .wake, isPowerSaving: false)
    #expect(!freshRetries, "a pending retry is not doubled")

    // In Low Power Mode the count still resets, but no retry runs: leaving Low Power Mode rebuilds instead.
    var lowPower = RecoveryBackoff()
    for _ in 0..<4 { _ = lowPower.nextDelay() }
    let lowPowerRetries = lowPower.reset(on: .unlock, isPowerSaving: true)
    #expect(!lowPowerRetries, "no retry in Low Power Mode")
    #expect(!lowPower.isResting, "the count resets in Low Power Mode too")
}

// MARK: - Folder change

private func action(
    toPlay: URL?, current: URL?, exists: Bool, recovering: Bool = false, powerSaving: Bool = false
) -> FolderChangeAction {
    folderChangeAction(
        toPlay: toPlay, current: current, currentExists: exists, isRecovering: recovering,
        isPowerSaving: powerSaving)
}

@Test func recoveryFolderChangeAction() {
    let rain = URL(fileURLWithPath: "/v/rain.mp4")
    let sea = URL(fileURLWithPath: "/v/sea.mp4")

    // Healthy playback switches only to a different video to play.
    #expect(action(toPlay: rain, current: rain, exists: true) == .keepPlaying)
    #expect(action(toPlay: sea, current: rain, exists: true) == .switchTo(sea))
    #expect(action(toPlay: sea, current: nil, exists: false) == .switchTo(sea))

    // The playing file vanished but another video is there: a logged Recovery that rebuilds now (the settle
    // check already debounced the burst of folder events).
    #expect(action(toPlay: sea, current: rain, exists: false) == .rebuildNow(.fileMissing))

    // No eligible video left: rest on the Poster (not a failure).
    #expect(action(toPlay: nil, current: rain, exists: false) == .restNoVideo)
    #expect(action(toPlay: nil, current: nil, exists: false, recovering: true) == .restNoVideo)

    // A video is back (returned or newly added) while Recovery is pending or resting: rebuild now, not after backoff.
    #expect(action(toPlay: rain, current: rain, exists: true, recovering: true) == .rebuildNow(.videoAvailable))
    #expect(action(toPlay: sea, current: rain, exists: true, recovering: true) == .rebuildNow(.videoAvailable))

    // In Low Power Mode nothing is built; leaving it rebuilds the video to play.
    #expect(action(toPlay: sea, current: rain, exists: true, powerSaving: true) == .holdForPower)
    #expect(action(toPlay: sea, current: rain, exists: false, powerSaving: true) == .holdForPower)
    #expect(action(toPlay: nil, current: rain, exists: false, powerSaving: true) == .holdForPower)
}
