import Foundation

// MARK: - Recovery
// Replacing a failed or stuck player so the Live wallpaper resumes without user action: the player is dropped at once
// (the Poster shows), then rebuilt after the backoff delay, or the Poster stays once every attempt is used.

extension PlaybackService {
    var isRecovering: Bool { pendingRebuild != nil || backoff.isResting || isRestingWithoutVideo }

    var recoveryState: RecoveryState {
        if pendingRebuild != nil { return .rebuilding(in: pendingRebuildDelay) }
        if backoff.isResting { return .resting }
        return isRestingWithoutVideo ? .waitingForVideo : .idle
    }

    /// Wake, unlock or a folder change: a rest on the Poster ends with a retry.
    public func resetBackoff(on event: RecoveryReset) {
        if backoff.reset(on: event, isPowerSaving: gate.isPowerSaving) {
            recover(cause: .retryAfterRest, detail: "on \(event.rawValue)")
        }
    }

    func recover(cause: RecoveryCause, detail: String) {
        guard !isRecovering else { return }
        let name = video.map(videoID)
        tearDown()
        guard let delay = backoff.nextDelay() else {
            onEvent(.recovery(.resting(
                cause: cause, video: name, attempts: RecoveryBackoff.delays.count, detail: detail)))
            return
        }
        // Scheduled before it is reported, so the snapshot taken with the event shows the rebuild pending.
        scheduleRebuild(after: delay)
        reportScheduled(cause, delay: delay, detail: detail)
    }

    /// The folder's set of videos changed: plays the Rotation's Current video `toPlay`, resets the backoff, and
    /// rebuilds promptly if the Current video's file is gone or a video became available while recovering, rather
    /// than waiting out the backoff timer.
    public func folderChanged(toPlay: URL?, fade: TimeInterval?) {
        // Read before the reset: a rest after an exhausted backoff is still Recovery and must be retried now.
        let wasRecovering = isRecovering
        backoff.reset(on: .folderChange, isPowerSaving: gate.isPowerSaving)
        let currentExists = video.map(fileExists) ?? false
        let action = folderChangeAction(
            toPlay: toPlay, current: video, currentExists: currentExists, isRecovering: wasRecovering,
            isPowerSaving: gate.isPowerSaving)
        switch action {
        case .keepPlaying:
            break
        case .switchTo(let url):
            play(url, fade: fade ?? Crossfade.quickDuration)
        case .rebuildNow(let cause):
            tearDown()
            isRestingWithoutVideo = false
            scheduleRebuild(after: 0)
            reportScheduled(cause, delay: 0, detail: "on folder-change")
        case .restNoVideo:
            restWithoutVideo(detail: "on folder-change")
        case .holdForPower:
            onEvent(.recovery(.folderChangeHeldForPower))
        }
    }

    private func reportScheduled(_ cause: RecoveryCause, delay: TimeInterval, detail: String) {
        onEvent(.recovery(.scheduled(
            cause: cause, video: video.map(videoID), position: savedSeconds, delay: delay, detail: detail)))
    }

    private func scheduleRebuild(after delay: TimeInterval) {
        pendingRebuild?.cancel()
        pendingRebuildDelay = delay
        pendingRebuild = clock.schedule(after: delay) { [weak self] in self?.rebuild() }
    }

    func cancelPendingRebuild() {
        pendingRebuild?.cancel()
        pendingRebuild = nil
    }

    private func rebuild() {
        pendingRebuild = nil
        runRebuildPlan(cause: .recovery)
    }

    func runRebuildPlan(cause: BuildCause) {
        let plan = rebuildPlan(
            toPlay: videoProvider(), current: video, saved: savedSeconds, isPowerSaving: gate.isPowerSaving)
        switch plan {
        case let .play(target, resumeAt):
            onEvent(.recovery(.built(cause: cause, video: videoID(target), at: resumeAt)))
            show(target, at: resumeAt)
        case .restNoVideo:
            restWithoutVideo(detail: "at \(cause.rawValue)")
        case .holdForPower:
            onEvent(.recovery(.heldForPower(cause: cause)))
        }
    }

    /// No eligible video: rest on the Poster until the folder changes. Not a failure, so the backoff is untouched.
    private func restWithoutVideo(detail: String) {
        cancelPendingRebuild()
        tearDown()
        guard !isRestingWithoutVideo else { return }
        isRestingWithoutVideo = true
        onEvent(.recovery(.restingWithoutVideo(video: video.map(videoID), detail: detail)))
    }
}
