import Foundation
@testable import Playback
import Testing

// MARK: - Playback gate tests

private let idle = RecoveryProgress()
private let exhausted = RecoveryProgress(isBackoffExhausted: true)

@Test func gateState() {
    let fresh = PlaybackGate()
    #expect(fresh.state == .playing)
    #expect(fresh.isIntendingToPlay, "nothing in the way: intends to play")

    var occluded = PlaybackGate()
    _ = occluded.apply(.allWindowsOccluded(true), recovery: idle)
    #expect(occluded.state == .paused)

    var asleep = PlaybackGate()
    _ = asleep.apply(.screensAsleep(true), recovery: idle)
    #expect(asleep.state == .paused)

    // Low Power Mode wins over every pause reason: the player is torn down, not just paused.
    var lowPower = PlaybackGate()
    _ = lowPower.apply(.allWindowsOccluded(true), recovery: idle)
    _ = lowPower.apply(.lowPower(true), recovery: idle)
    #expect(lowPower.state == .posterOnly)
    #expect(lowPower.isPowerSaving, "Low Power Mode is power saving")
}

@Test func gateTransition() {
    var gate = PlaybackGate()
    #expect(gate.apply(.allWindowsOccluded(true), recovery: idle).action == .pause)
    // A second pause reason changes nothing; only the last one clearing resumes.
    #expect(gate.apply(.screensAsleep(true), recovery: idle).action == PlaybackGateAction.none)
    #expect(gate.apply(.allWindowsOccluded(false), recovery: idle).action == PlaybackGateAction.none)
    #expect(gate.apply(.screensAsleep(false), recovery: idle).action == .resume)

    // Repeated identical events (occlusion notifications fire per window) do nothing.
    #expect(gate.apply(.allWindowsOccluded(false), recovery: idle).action == PlaybackGateAction.none)

    #expect(gate.apply(.lowPower(true), recovery: idle).action == .tearDown)
    #expect(gate.apply(.lowPower(true), recovery: idle).action == PlaybackGateAction.none)
    // Pause reasons change while torn down: nothing to pause or resume.
    #expect(gate.apply(.allWindowsOccluded(true), recovery: idle).action == PlaybackGateAction.none)
    #expect(gate.apply(.allWindowsOccluded(false), recovery: idle).action == PlaybackGateAction.none)

    // From paused straight into Low Power Mode also tears down.
    var paused = PlaybackGate()
    _ = paused.apply(.screensAsleep(true), recovery: idle)
    #expect(paused.apply(.lowPower(true), recovery: idle).action == .tearDown)
}

@Test func gateLowPowerExit() {
    var gate = PlaybackGate()
    _ = gate.apply(.lowPower(true), recovery: idle)
    #expect(gate.apply(.lowPower(false), recovery: idle).action == .rebuild)
    #expect(gate.state == .playing)

    // Leaving Low Power Mode while covered still rebuilds; the new player just stays paused.
    var covered = PlaybackGate()
    _ = covered.apply(.lowPower(true), recovery: idle)
    _ = covered.apply(.allWindowsOccluded(true), recovery: idle)
    #expect(covered.apply(.lowPower(false), recovery: idle).action == .rebuild)
    #expect(covered.state == .paused)

    // A broken file that exhausted its backoff keeps resting on the Poster until wake, unlock or folder change.
    var resting = PlaybackGate()
    _ = resting.apply(.lowPower(true), recovery: exhausted)
    #expect(resting.apply(.lowPower(false), recovery: exhausted).action == PlaybackGateAction.none)
    #expect(resting.state == .playing)
}

@Test func gateRecoveryProgress() {
    // Entering Low Power Mode drops a pending rebuild and a no-video rest: leaving it re-picks and rebuilds.
    var gate = PlaybackGate()
    let pending = RecoveryProgress(isRebuildPending: true, isRestingWithoutVideo: false, isBackoffExhausted: false)
    #expect(gate.apply(.lowPower(true), recovery: pending) == PlaybackDecision(action: .tearDown, recovery: idle))
    #expect(gate.apply(.lowPower(false), recovery: idle) == PlaybackDecision(action: .rebuild, recovery: idle))

    var noVideo = PlaybackGate()
    let resting = RecoveryProgress(isRebuildPending: false, isRestingWithoutVideo: true, isBackoffExhausted: false)
    #expect(noVideo.apply(.lowPower(true), recovery: resting) == PlaybackDecision(action: .tearDown, recovery: idle))

    // An exhausted backoff survives Low Power Mode, so leaving it does not retry the broken file.
    var broken = PlaybackGate()
    let both = RecoveryProgress(isRebuildPending: false, isRestingWithoutVideo: true, isBackoffExhausted: true)
    #expect(broken.apply(.lowPower(true), recovery: both) == PlaybackDecision(action: .tearDown, recovery: exhausted))
    #expect(broken.apply(.lowPower(false), recovery: exhausted) == PlaybackDecision(action: .none, recovery: exhausted))

    // Pausing for occlusion or sleep leaves a pending rebuild alone: it builds a paused player.
    var covered = PlaybackGate()
    #expect(
        covered.apply(.allWindowsOccluded(true), recovery: pending)
            == PlaybackDecision(action: .pause, recovery: pending))
}

/// Recovery must never treat a deliberate pause or tear-down as a stuck player.
@Test func gateRecoveryIntent() {
    let inputs: [PlaybackInput] = [.lowPower(true), .allWindowsOccluded(true), .screensAsleep(true)]
    for input in inputs {
        var gate = PlaybackGate()
        _ = gate.apply(input, recovery: idle)
        #expect(!gate.isIntendingToPlay, "\(input) is not an intent to play")
        var monitor = RecoveryMonitor()
        for now in stride(from: 0.0, through: 30, by: 5) {
            let sample = HealthSample(
                now: now, playbackSeconds: 4, isIntendingToPlay: gate.isIntendingToPlay, hasFailed: false)
            #expect(monitor.tick(sample) == nil)
        }
        let verdict = monitor.verdictAfterWake(
            at: 100, timeAdvanced: false, isIntendingToPlay: gate.isIntendingToPlay, hasFailed: false)
        #expect(verdict == nil)
    }
}
