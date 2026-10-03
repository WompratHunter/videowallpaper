import AppKit
import AVFoundation

// MARK: - Shared player
// One decoder feeds every display: each window hosts an AVPlayerLayer bound to the same queue player, above
// a Poster layer that shares one decoded image. Tearing the player down therefore reveals the Poster, never black.

final class Player {
    /// Picks the video to play when a rebuild runs, so a renamed or deleted file is replaced ("newest wins").
    var videoProvider: () -> URL? = { nil }
    /// Called when a rebuild switches to a different video, so its Poster can be regenerated.
    var onVideoChange: (URL) -> Void = { _ in }

    private(set) var video: URL?
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var observations: [NSKeyValueObservation] = []
    private var failureObserver: NSObjectProtocol?
    private let layers = PlayerLayers()
    private var monitor = RecoveryMonitor()
    private var backoff = RecoveryBackoff()
    private var pendingRebuild: DispatchWorkItem?
    private var pendingSeek: Double?
    private var savedSeconds: Double = 0
    private var gate = PlaybackGate()
    private var isRestingWithoutVideo = false

    private var shouldBePlaying: Bool { gate.isIntendingToPlay && video != nil }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    init() {
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let item = note.object as? AVPlayerItem,
                  self.queuePlayer?.items().contains(item) == true
            else { return }
            let error = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error).map(describe)
            self.recover(cause: .failed, detail: "failed-to-play-to-end \(error ?? "")")
        }
    }

    deinit {
        failureObserver.map(NotificationCenter.default.removeObserver)
        pendingRebuild?.cancel()
    }

    // MARK: - Playback

    func show(_ url: URL, at seconds: Double = 0) {
        pendingRebuild?.cancel()
        pendingRebuild = nil
        isRestingWithoutVideo = false
        tearDown()
        let changed = url != video
        video = url
        savedSeconds = seconds
        pendingSeek = seconds > 0 ? seconds : nil
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        let newLooper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        looper = newLooper
        observe(player, newLooper)
        layers.attach(player)
        monitor.noteRebuild(at: now)
        if gate.isIntendingToPlay && pendingSeek == nil { player.play() }
        if changed { onVideoChange(url) }
    }

    /// Goes through the rebuild plan so launching in Low Power Mode, or with no video, holds on the Poster.
    func start() {
        runRebuildPlan(verb: "playing", cause: "launch")
    }

    func resetBackoff(on event: RecoveryBackoff.ResetEvent) {
        if backoff.reset(on: event, isPowerSaving: gate.isPowerSaving) {
            recover(cause: .retryAfterRest, detail: "on \(event.rawValue)")
        }
    }

    // MARK: - Health

    /// Runs on the app's shared 5 s tick: compares playback time with the previous tick.
    func healthTick() {
        guard !isRecovering else { return }
        let seconds = playbackSeconds
        let sample = HealthSample(
            now: now, playbackSeconds: seconds, isIntendingToPlay: shouldBePlaying, hasFailed: hasFailed)
        if let cause = monitor.tick(sample) {
            recover(cause: cause, detail: stateReport(sinceSeconds: nil).description)
        } else if gate.isIntendingToPlay {
            savePosition()
        }
    }

    /// Samples playback now and a moment later, logs the state, and rebuilds only if not actually playing.
    func verifyPlayback(cause: String) {
        let sampledPlayer = queuePlayer
        let earlier = playbackSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            let report = self.stateReport(sinceSeconds: earlier)
            Log.write(cause, "video=\(self.video?.lastPathComponent ?? "none") \(report)")
            // A player swapped in during the sample isn't comparable, and was just rebuilt anyway.
            guard self.queuePlayer === sampledPlayer else { return }
            let verdict = self.monitor.verdictAfterWake(
                at: self.now, timeAdvanced: report.timeAdvanced,
                isIntendingToPlay: self.shouldBePlaying, hasFailed: self.hasFailed)
            if let verdict { self.recover(cause: verdict, detail: "on \(cause)") }
        }
    }

    private func tearDown() {
        observations.forEach { $0.invalidate() }
        observations = []
        looper?.disableLooping()
        looper = nil
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        queuePlayer = nil
        pendingSeek = nil
        layers.attach(nil)
    }
}

// MARK: - Recovery

extension Player {
    private var isRecovering: Bool { pendingRebuild != nil || backoff.isResting || isRestingWithoutVideo }

    /// Drops the player at once (the Poster shows), then rebuilds after the backoff delay or rests on the Poster.
    func recover(cause: RecoveryCause, detail: String) {
        guard !isRecovering else { return }
        let name = video?.lastPathComponent ?? "none"
        tearDown()
        guard let delay = backoff.nextDelay() else {
            Log.write("recovery", "cause=\(cause.rawValue) video=\(name) resting on Poster after "
                + "\(RecoveryBackoff.delays.count) attempts \(detail)")
            return
        }
        logRecovery(cause, rebuildIn: delay, detail: detail)
        scheduleRebuild(after: delay)
    }

    /// The folder's set of videos changed: resets the backoff, and rebuilds promptly if a video became available
    /// while recovering, rather than waiting out the backoff timer.
    func folderChanged(newest: URL?) {
        // Read before the reset: a rest after an exhausted backoff is still Recovery and must be retried now.
        let wasRecovering = isRecovering
        backoff.reset(on: .folderChange, isPowerSaving: gate.isPowerSaving)
        let currentExists = video.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let action = folderChangeAction(
            newest: newest, current: video, currentExists: currentExists, isRecovering: wasRecovering,
            isPowerSaving: gate.isPowerSaving)
        switch action {
        case .keepPlaying:
            break
        case .switchTo(let url):
            show(url)
        case .rebuildNow(let cause):
            tearDown()
            isRestingWithoutVideo = false
            logRecovery(cause, rebuildIn: 0, detail: "on folder-change")
            scheduleRebuild(after: 0)
        case .restNoVideo:
            restWithoutVideo(detail: "on folder-change")
        case .holdForPower:
            Log.write("folder-change", "Low Power Mode: the newest video loads when it ends")
        }
    }

    private func logRecovery(_ cause: RecoveryCause, rebuildIn delay: TimeInterval, detail: String) {
        Log.write("recovery", "cause=\(cause.rawValue) video=\(video?.lastPathComponent ?? "none") "
            + "position=\(format(savedSeconds)) rebuild-in=\(Int(delay))s \(detail)")
    }

    private func scheduleRebuild(after delay: TimeInterval) {
        pendingRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rebuild() }
        pendingRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func rebuild() {
        pendingRebuild = nil
        runRebuildPlan(verb: "rebuilding", cause: "recovery")
    }

    private func runRebuildPlan(verb: String, cause: String) {
        let plan = rebuildPlan(
            newest: videoProvider(), current: video, saved: savedSeconds, isPowerSaving: gate.isPowerSaving)
        switch plan {
        case let .play(target, resumeAt):
            Log.write(cause, "\(verb) video=\(target.lastPathComponent) at=\(format(resumeAt))")
            show(target, at: resumeAt)
        case .restNoVideo:
            restWithoutVideo(detail: "at \(cause)")
        case .holdForPower:
            Log.write(cause, "Low Power Mode: holding on the Poster")
        }
    }

    /// No eligible video: rest on the Poster until the folder changes. Not a failure, so the backoff is untouched.
    private func restWithoutVideo(detail: String) {
        pendingRebuild?.cancel()
        pendingRebuild = nil
        tearDown()
        guard !isRestingWithoutVideo else { return }
        isRestingWithoutVideo = true
        Log.write("recovery", "cause=no-video video=\(video?.lastPathComponent ?? "none") "
            + "resting on Poster until a video is added \(detail)")
    }
}

// MARK: - Low Power Mode, occlusion and screen sleep

extension Player {
    /// Applies a deliberate reason to stop or start playing; the gate decides what that means for the player.
    func apply(_ event: PlaybackEvent) {
        let decision = gate.apply(event, recovery: recoveryState)
        applyRecovery(decision.recovery)
        let action = decision.action
        guard action != .none else { return }
        Log.write("playback", "event=\(event) action=\(action) mode=\(gate.mode) "
            + "video=\(video?.lastPathComponent ?? "none")")
        switch action {
        case .none:
            break
        case .pause:
            savePosition()
            queuePlayer?.pause()
        case .resume:
            monitor.noteResume(at: now)
            if pendingSeek == nil { queuePlayer?.play() }
        case .tearDown:
            savePosition()
            tearDown()
        case .rebuild:
            runRebuildPlan(verb: "rebuilding", cause: "power")
        }
    }

    private var recoveryState: RecoveryState {
        RecoveryState(
            isRebuildPending: pendingRebuild != nil, isRestingWithoutVideo: isRestingWithoutVideo,
            isBackoffExhausted: backoff.isResting)
    }

    /// The gate only ever clears Recovery state; the backoff count is never changed by it.
    private func applyRecovery(_ next: RecoveryState) {
        if !next.isRebuildPending {
            pendingRebuild?.cancel()
            pendingRebuild = nil
        }
        isRestingWithoutVideo = next.isRestingWithoutVideo
    }

    /// Not while a resume seek is pending: currentTime() is still 0 and would lose the saved position.
    private func savePosition() {
        if pendingSeek == nil, let seconds = playbackSeconds { savedSeconds = seconds }
    }
}

// MARK: - Layers

extension Player {
    /// A Poster layer with the video layer above it, sized to `frame`; the caller's window only hosts it.
    func makeLayers(frame: CGRect) -> CALayer { layers.make(frame: frame) }

    func setPoster(_ image: CGImage) { layers.setPoster(image) }
}

// MARK: - Observation and state

extension Player {
    private var playbackSeconds: Double? {
        guard let time = queuePlayer?.currentTime(), time.isNumeric else { return nil }
        return time.seconds
    }

    private var hasFailed: Bool { queuePlayer?.hasFailed(looper: looper) ?? false }

    private func stateReport(sinceSeconds earlier: Double?) -> PlayerStateReport {
        guard let queuePlayer else { return .noPlayer }
        return queuePlayer.stateReport(
            looper: looper, timeAdvanced: playbackAdvanced(from: earlier, to: playbackSeconds))
    }

    private func observe(_ player: AVQueuePlayer, _ looper: AVPlayerLooper) {
        let itemStatus = player.observe(\.currentItem?.status, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.itemStatusChanged() }
        }
        let looperStatus = looper.observe(\.status, options: [.new]) { [weak self] looper, _ in
            guard looper.status == .failed else { return }
            DispatchQueue.main.async { self?.reportFailure("looper failed") }
        }
        observations = [itemStatus, looperStatus]
    }

    private func itemStatusChanged() {
        guard let player = queuePlayer, let item = player.currentItem else { return }
        switch item.status {
        case .failed:
            reportFailure("item failed")
        case .readyToPlay:
            guard let seconds = pendingSeek else { return }
            // Seek before playing so a rebuilt player resumes where the old one stopped, not at 0.
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { [weak self, weak player] _ in
                DispatchQueue.main.async {
                    guard let self, let player, player === self.queuePlayer else { return }
                    self.pendingSeek = nil
                    if self.gate.isIntendingToPlay { player.play() }
                }
            }
        default:
            break
        }
    }

    private func reportFailure(_ what: String) {
        recover(cause: .failed, detail: "\(what) \(stateReport(sinceSeconds: nil))")
    }

    private func format(_ seconds: Double) -> String { String(format: "%.1f", seconds) }
}
