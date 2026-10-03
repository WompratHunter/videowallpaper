import Foundation

// MARK: - Recovery tests

func runRecoveryTests() {
    runStuckTests()
    runNoIntentTests()
    runFailedTests()
    runGraceTests()
    runWakeTests()
    runBackoffTests()
}

private func sample(
    at now: TimeInterval, _ seconds: Double?, intending: Bool = true, failed: Bool = false
) -> HealthSample {
    HealthSample(now: now, playbackSeconds: seconds, isIntendingToPlay: intending, hasFailed: failed)
}

private func runStuckTests() {
    var monitor = RecoveryMonitor()
    checkEqual(monitor.tick(sample(at: 100, 4.0)), nil)
    checkEqual(monitor.tick(sample(at: 105, 4.0)), nil)
    checkEqual(monitor.tick(sample(at: 110, 4.0)), .stuck)

    // A single frozen tick between advancing ones is not a stall.
    var flaky = RecoveryMonitor()
    for (now, seconds) in [(0.0, 1.0), (5, 1.0), (10, 6.0), (15, 6.0), (20, 11.0)] {
        checkEqual(flaky.tick(sample(at: now, seconds)), nil)
    }

    // A player with no current time (item gone) is not advancing.
    var vanished = RecoveryMonitor()
    checkEqual(vanished.tick(sample(at: 0, 2.0)), nil)
    checkEqual(vanished.tick(sample(at: 5, nil)), nil)
    checkEqual(vanished.tick(sample(at: 10, nil)), .stuck)
}

private func runNoIntentTests() {
    // Paused on purpose (screens asleep): frozen time is expected, so those ticks never count.
    var monitor = RecoveryMonitor()
    checkEqual(monitor.tick(sample(at: 0, 3.0)), nil)
    checkEqual(monitor.tick(sample(at: 5, 3.0, intending: false)), nil)
    checkEqual(monitor.tick(sample(at: 10, 3.0, intending: false)), nil)
    checkEqual(monitor.tick(sample(at: 15, 3.0, intending: false, failed: true)), nil)
    // Resuming starts a fresh baseline rather than comparing against the paused time.
    checkEqual(monitor.tick(sample(at: 20, 3.0)), nil)
    checkEqual(monitor.tick(sample(at: 25, 8.0)), nil)
}

private func runFailedTests() {
    // A failed item is rebuilt on the first tick that sees it, without waiting for a stall.
    var monitor = RecoveryMonitor()
    checkEqual(monitor.tick(sample(at: 0, 2.0, failed: true)), .failed)
    var playing = RecoveryMonitor()
    checkEqual(playing.tick(sample(at: 0, 2.0)), nil)
    checkEqual(playing.tick(sample(at: 5, 7.0, failed: true)), .failed)
}

private func runGraceTests() {
    var monitor = RecoveryMonitor()
    monitor.noteRebuild(at: 100)
    // Loading a rebuilt item can take a while: no stall verdict within 15 s of the rebuild.
    checkEqual(monitor.tick(sample(at: 101, 0.0)), nil)
    checkEqual(monitor.tick(sample(at: 106, 0.0)), nil)
    checkEqual(monitor.tick(sample(at: 111, 0.0)), nil)
    // After the grace window, two stalled ticks are needed again.
    checkEqual(monitor.tick(sample(at: 116, 0.0)), nil)
    checkEqual(monitor.tick(sample(at: 121, 0.0)), .stuck)

    // A failure is definitive, so grace does not hide it.
    var failing = RecoveryMonitor()
    failing.noteRebuild(at: 100)
    checkEqual(failing.tick(sample(at: 102, nil, failed: true)), .failed)

    // A rebuild discards stalls counted against the old player.
    var stalled = RecoveryMonitor()
    checkEqual(stalled.tick(sample(at: 0, 5.0)), nil)
    checkEqual(stalled.tick(sample(at: 5, 5.0)), nil)
    stalled.noteRebuild(at: 6)
    checkEqual(stalled.tick(sample(at: 25, 5.0)), nil)
    checkEqual(stalled.tick(sample(at: 30, 9.0)), nil)
}

private func runWakeTests() {
    // A healthy player is never interrupted on wake or unlock.
    checkEqual(RecoveryMonitor.verdictAfterWake(timeAdvanced: true, isIntendingToPlay: true, hasFailed: false), nil)
    checkEqual(
        RecoveryMonitor.verdictAfterWake(timeAdvanced: false, isIntendingToPlay: true, hasFailed: false),
        .notPlayingOnWake)
    checkEqual(
        RecoveryMonitor.verdictAfterWake(timeAdvanced: nil, isIntendingToPlay: true, hasFailed: false),
        .notPlayingOnWake)
    checkEqual(RecoveryMonitor.verdictAfterWake(timeAdvanced: true, isIntendingToPlay: true, hasFailed: true), .failed)
    checkEqual(RecoveryMonitor.verdictAfterWake(timeAdvanced: nil, isIntendingToPlay: false, hasFailed: true), nil)
}

private func runBackoffTests() {
    var backoff = RecoveryBackoff()
    checkEqual(backoff.nextDelay(), 10)
    checkEqual(backoff.nextDelay(), 60)
    checkEqual(backoff.nextDelay(), 300)
    // After three failed attempts a truly broken file rests on the Poster instead of burning CPU.
    checkEqual(backoff.nextDelay(), nil)
    checkEqual(backoff.nextDelay(), nil)
    check(backoff.isResting, "resting after the schedule is exhausted")

    // Wake, unlock and folder change all reset the count, so one bad night doesn't strand a good video.
    for event in [RecoveryBackoff.ResetEvent.wake, .unlock, .folderChange] {
        var used = RecoveryBackoff()
        for _ in 0..<4 { _ = used.nextDelay() }
        used.reset(on: event)
        check(!used.isResting, "not resting after reset on \(event)")
        checkEqual(used.nextDelay(), 10)
    }
}
