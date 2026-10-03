import Foundation

// MARK: - Playback gate tests

private let idle = RecoveryState()
private let exhausted = RecoveryState(isBackoffExhausted: true)

func runPlaybackGateTests() {
    runGateModeTests()
    runGateTransitionTests()
    runGateLowPowerExitTests()
    runGateRecoveryStateTests()
    runGateRecoveryIntentTests()
}

private func runGateModeTests() {
    let fresh = PlaybackGate()
    checkEqual(fresh.mode, .playing)
    check(fresh.isIntendingToPlay, "nothing in the way: intends to play")

    var occluded = PlaybackGate()
    _ = occluded.apply(.allWindowsOccluded(true), recovery: idle)
    checkEqual(occluded.mode, .paused)

    var asleep = PlaybackGate()
    _ = asleep.apply(.screensAsleep(true), recovery: idle)
    checkEqual(asleep.mode, .paused)

    // Low Power Mode wins over every pause reason: the player is torn down, not just paused.
    var lowPower = PlaybackGate()
    _ = lowPower.apply(.allWindowsOccluded(true), recovery: idle)
    _ = lowPower.apply(.lowPower(true), recovery: idle)
    checkEqual(lowPower.mode, .posterOnly)
    check(lowPower.isPowerSaving, "Low Power Mode is power saving")
}

private func runGateTransitionTests() {
    var gate = PlaybackGate()
    checkEqual(gate.apply(.allWindowsOccluded(true), recovery: idle).action, .pause)
    // A second pause reason changes nothing; only the last one clearing resumes.
    checkEqual(gate.apply(.screensAsleep(true), recovery: idle).action, PlaybackGateAction.none)
    checkEqual(gate.apply(.allWindowsOccluded(false), recovery: idle).action, PlaybackGateAction.none)
    checkEqual(gate.apply(.screensAsleep(false), recovery: idle).action, .resume)

    // Repeated identical events (occlusion notifications fire per window) do nothing.
    checkEqual(gate.apply(.allWindowsOccluded(false), recovery: idle).action, PlaybackGateAction.none)

    checkEqual(gate.apply(.lowPower(true), recovery: idle).action, .tearDown)
    checkEqual(gate.apply(.lowPower(true), recovery: idle).action, PlaybackGateAction.none)
    // Pause reasons change while torn down: nothing to pause or resume.
    checkEqual(gate.apply(.allWindowsOccluded(true), recovery: idle).action, PlaybackGateAction.none)
    checkEqual(gate.apply(.allWindowsOccluded(false), recovery: idle).action, PlaybackGateAction.none)

    // From paused straight into Low Power Mode also tears down.
    var paused = PlaybackGate()
    _ = paused.apply(.screensAsleep(true), recovery: idle)
    checkEqual(paused.apply(.lowPower(true), recovery: idle).action, .tearDown)
}

private func runGateLowPowerExitTests() {
    var gate = PlaybackGate()
    _ = gate.apply(.lowPower(true), recovery: idle)
    checkEqual(gate.apply(.lowPower(false), recovery: idle).action, .rebuild)
    checkEqual(gate.mode, .playing)

    // Leaving Low Power Mode while covered still rebuilds; the new player just stays paused.
    var covered = PlaybackGate()
    _ = covered.apply(.lowPower(true), recovery: idle)
    _ = covered.apply(.allWindowsOccluded(true), recovery: idle)
    checkEqual(covered.apply(.lowPower(false), recovery: idle).action, .rebuild)
    checkEqual(covered.mode, .paused)

    // A broken file that exhausted its backoff keeps resting on the Poster until wake, unlock or folder change.
    var resting = PlaybackGate()
    _ = resting.apply(.lowPower(true), recovery: exhausted)
    checkEqual(resting.apply(.lowPower(false), recovery: exhausted).action, PlaybackGateAction.none)
    checkEqual(resting.mode, .playing)
}

private func runGateRecoveryStateTests() {
    // Entering Low Power Mode drops a pending rebuild and a no-video rest: leaving it re-picks and rebuilds.
    var gate = PlaybackGate()
    let pending = RecoveryState(isRebuildPending: true, isRestingWithoutVideo: false, isBackoffExhausted: false)
    checkEqual(gate.apply(.lowPower(true), recovery: pending), PlaybackDecision(action: .tearDown, recovery: idle))
    checkEqual(gate.apply(.lowPower(false), recovery: idle), PlaybackDecision(action: .rebuild, recovery: idle))

    var noVideo = PlaybackGate()
    let resting = RecoveryState(isRebuildPending: false, isRestingWithoutVideo: true, isBackoffExhausted: false)
    checkEqual(noVideo.apply(.lowPower(true), recovery: resting), PlaybackDecision(action: .tearDown, recovery: idle))

    // An exhausted backoff survives Low Power Mode, so leaving it does not retry the broken file.
    var broken = PlaybackGate()
    let both = RecoveryState(isRebuildPending: false, isRestingWithoutVideo: true, isBackoffExhausted: true)
    checkEqual(
        broken.apply(.lowPower(true), recovery: both), PlaybackDecision(action: .tearDown, recovery: exhausted))
    checkEqual(
        broken.apply(.lowPower(false), recovery: exhausted), PlaybackDecision(action: .none, recovery: exhausted))

    // Pausing for occlusion or sleep leaves a pending rebuild alone: it builds a paused player.
    var covered = PlaybackGate()
    checkEqual(
        covered.apply(.allWindowsOccluded(true), recovery: pending),
        PlaybackDecision(action: .pause, recovery: pending))
}

/// Recovery must never treat a deliberate pause or tear-down as a stuck player.
private func runGateRecoveryIntentTests() {
    let events: [PlaybackEvent] = [.lowPower(true), .allWindowsOccluded(true), .screensAsleep(true)]
    for event in events {
        var gate = PlaybackGate()
        _ = gate.apply(event, recovery: idle)
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
