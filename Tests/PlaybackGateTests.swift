import Foundation

// MARK: - Playback gate tests

func runPlaybackGateTests() {
    runGateModeTests()
    runGateTransitionTests()
    runGateLowPowerExitTests()
    runGateRecoveryIntentTests()
    runOcclusionTests()
}

private func runGateModeTests() {
    let idle = PlaybackGate()
    checkEqual(idle.mode, .playing)
    check(idle.isIntendingToPlay, "nothing in the way: intends to play")

    var occluded = PlaybackGate()
    _ = occluded.apply(.allWindowsOccluded(true), isRecoveryResting: false)
    checkEqual(occluded.mode, .paused)

    var asleep = PlaybackGate()
    _ = asleep.apply(.screensAsleep(true), isRecoveryResting: false)
    checkEqual(asleep.mode, .paused)

    // Low Power Mode wins over every pause reason: the player is torn down, not just paused.
    var lowPower = PlaybackGate()
    _ = lowPower.apply(.allWindowsOccluded(true), isRecoveryResting: false)
    _ = lowPower.apply(.lowPower(true), isRecoveryResting: false)
    checkEqual(lowPower.mode, .posterOnly)
    check(lowPower.isPowerSaving, "Low Power Mode is power saving")
}

private func runGateTransitionTests() {
    var gate = PlaybackGate()
    checkEqual(gate.apply(.allWindowsOccluded(true), isRecoveryResting: false), .pause)
    // A second pause reason changes nothing; only the last one clearing resumes.
    checkEqual(gate.apply(.screensAsleep(true), isRecoveryResting: false), PlaybackGateAction.none)
    checkEqual(gate.apply(.allWindowsOccluded(false), isRecoveryResting: false), PlaybackGateAction.none)
    checkEqual(gate.apply(.screensAsleep(false), isRecoveryResting: false), .resume)

    // Repeated identical events (occlusion notifications fire per window) do nothing.
    checkEqual(gate.apply(.allWindowsOccluded(false), isRecoveryResting: false), PlaybackGateAction.none)

    checkEqual(gate.apply(.lowPower(true), isRecoveryResting: false), .tearDown)
    checkEqual(gate.apply(.lowPower(true), isRecoveryResting: false), PlaybackGateAction.none)
    // Pause reasons change while torn down: nothing to pause or resume.
    checkEqual(gate.apply(.allWindowsOccluded(true), isRecoveryResting: false), PlaybackGateAction.none)
    checkEqual(gate.apply(.allWindowsOccluded(false), isRecoveryResting: false), PlaybackGateAction.none)

    // From paused straight into Low Power Mode also tears down.
    var paused = PlaybackGate()
    _ = paused.apply(.screensAsleep(true), isRecoveryResting: false)
    checkEqual(paused.apply(.lowPower(true), isRecoveryResting: false), .tearDown)
}

private func runGateLowPowerExitTests() {
    var gate = PlaybackGate()
    _ = gate.apply(.lowPower(true), isRecoveryResting: false)
    checkEqual(gate.apply(.lowPower(false), isRecoveryResting: false), .rebuild)
    checkEqual(gate.mode, .playing)

    // Leaving Low Power Mode while covered still rebuilds; the new player just stays paused.
    var covered = PlaybackGate()
    _ = covered.apply(.lowPower(true), isRecoveryResting: false)
    _ = covered.apply(.allWindowsOccluded(true), isRecoveryResting: false)
    checkEqual(covered.apply(.lowPower(false), isRecoveryResting: false), .rebuild)
    checkEqual(covered.mode, .paused)

    // A broken file that exhausted its backoff keeps resting on the Poster until wake, unlock or folder change.
    var resting = PlaybackGate()
    _ = resting.apply(.lowPower(true), isRecoveryResting: true)
    checkEqual(resting.apply(.lowPower(false), isRecoveryResting: true), PlaybackGateAction.none)
    checkEqual(resting.mode, .playing)
}

/// Recovery must never treat a deliberate pause or tear-down as a stuck player.
private func runGateRecoveryIntentTests() {
    let events: [PlaybackEvent] = [.lowPower(true), .allWindowsOccluded(true), .screensAsleep(true)]
    for event in events {
        var gate = PlaybackGate()
        _ = gate.apply(event, isRecoveryResting: false)
        check(!gate.isIntendingToPlay, "\(event) is not an intent to play")
        var monitor = RecoveryMonitor()
        for now in stride(from: 0.0, through: 30, by: 5) {
            let sample = HealthSample(
                now: now, playbackSeconds: 4, isIntendingToPlay: gate.isIntendingToPlay, hasFailed: false)
            checkEqual(monitor.tick(sample), nil)
        }
        let verdict = monitor.verdictAfterWake(
            at: 100, timeAdvanced: false, isIntendingToPlay: gate.isIntendingToPlay, hasFailed: false)
        checkEqual(verdict, nil)
    }
}

private func runOcclusionTests() {
    check(areAllWindowsOccluded(visibility: [false, false, false]), "every window covered")
    check(!areAllWindowsOccluded(visibility: [false, true, false]), "one visible display keeps playing")
    check(!areAllWindowsOccluded(visibility: []), "no windows is not occluded")
}
