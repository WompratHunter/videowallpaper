import Foundation

// MARK: - Low Power Mode, occlusion and screen sleep
// Every deliberate reason to stop or start playing goes through the gate, which decides the Playback state and what
// that means for the player.

extension PlaybackService {
    /// Applies a deliberate reason to stop or start playing.
    public func apply(_ input: PlaybackInput) {
        let decision = gate.apply(input, recovery: recoveryProgress)
        applyRecovery(decision.recovery)
        let action = decision.action
        guard action != .none else { return }
        onEvent(.stateChanged(input: input, action: action, state: gate.state, video: video.map(videoID)))
        switch action {
        case .none:
            break
        case .pause:
            savePosition()
            player.pause()
            apply(crossfade.pause())
        case .resume:
            monitor.noteResume(at: now)
            if pendingSeek == nil { player.play() }
        case .tearDown:
            savePosition()
            tearDown()
        case .rebuild:
            runRebuildPlan(cause: .power)
        }
    }

    /// The screens went to sleep: nobody can see the video, so it pauses.
    public func screensDidSleep() {
        onEvent(.screensAsleep)
        apply(.screensAsleep(true))
    }

    /// Low Power Mode turned on or off: returns whether it is on now.
    public func lowPowerModeChanged() -> Bool {
        let isOn = isLowPowerMode
        onEvent(.lowPowerModeChanged(isOn: isOn))
        apply(.lowPower(isOn))
        return isOn
    }

    /// Published for the coordinator, which forwards it to the gate (`apply(.allWindowsOccluded(_:))`) and Presence.
    func occlusionChanged(_ change: OcclusionChange, isEveryWindowOccluded: Bool) {
        self.isEveryWindowOccluded = isEveryWindowOccluded
        onEvent(.occlusionChanged(change, isEveryWindowOccluded: isEveryWindowOccluded))
    }

    private var recoveryProgress: RecoveryProgress {
        RecoveryProgress(
            isRebuildPending: pendingRebuild != nil, isRestingWithoutVideo: isRestingWithoutVideo,
            isBackoffExhausted: backoff.isResting)
    }

    /// The gate only ever clears Recovery progress; the backoff count is never changed by it.
    private func applyRecovery(_ next: RecoveryProgress) {
        if !next.isRebuildPending { cancelPendingRebuild() }
        isRestingWithoutVideo = next.isRestingWithoutVideo
    }
}
