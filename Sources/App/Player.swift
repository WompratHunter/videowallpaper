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
    private let videoLayers = NSHashTable<AVPlayerLayer>.weakObjects()
    private let posterLayers = NSHashTable<CALayer>.weakObjects()
    private var poster: CGImage?
    private var monitor = RecoveryMonitor()
    private var backoff = RecoveryBackoff()
    private var pendingRebuild: DispatchWorkItem?
    private var pendingSeek: Double?
    private var savedSeconds: Double = 0
    private var isIntendingToPlay = true

    private var failureObserver: NSObjectProtocol?

    init() {
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let item = note.object as? AVPlayerItem,
                  self.queuePlayer?.items().contains(item) == true
            else { return }
            let error = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error).map(describe)
            self.recover(cause: RecoveryCause.failed.rawValue, detail: "failed-to-play-to-end \(error ?? "")")
        }
    }

    // MARK: - Layers

    /// A Poster layer with the video layer above it, sized to `frame`; the caller's window only hosts it.
    func makeLayers(frame: CGRect) -> CALayer {
        let container = CALayer()
        container.frame = frame
        let posterLayer = CALayer()
        posterLayer.frame = container.bounds
        posterLayer.contentsGravity = .resizeAspectFill
        posterLayer.masksToBounds = true
        posterLayer.contents = poster
        let videoLayer = AVPlayerLayer()
        videoLayer.frame = container.bounds
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.player = queuePlayer
        container.addSublayer(posterLayer)
        container.addSublayer(videoLayer)
        posterLayers.add(posterLayer)
        videoLayers.add(videoLayer)
        return container
    }

    func setPoster(_ image: CGImage) {
        poster = image
        posterLayers.allObjects.forEach { $0.contents = image }
    }

    // MARK: - Playback

    func show(_ url: URL, at seconds: Double = 0) {
        pendingRebuild?.cancel()
        pendingRebuild = nil
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
        observe(player, newLooper)
        queuePlayer = player
        looper = newLooper
        videoLayers.allObjects.forEach { $0.player = player }
        monitor.noteRebuild(at: ProcessInfo.processInfo.systemUptime)
        if isIntendingToPlay && pendingSeek == nil { player.play() }
        if changed { onVideoChange(url) }
    }

    func pause() {
        isIntendingToPlay = false
        if let seconds = playbackSeconds { savedSeconds = seconds }
        queuePlayer?.pause()
    }

    func resume() {
        isIntendingToPlay = true
        if pendingSeek == nil { queuePlayer?.play() }
    }

    func resetBackoff(on event: RecoveryBackoff.ResetEvent) {
        let wasResting = backoff.isResting
        backoff.reset(on: event)
        if wasResting { Log.write(event.rawValue, "recovery backoff reset; leaving Poster rest") }
    }

    // MARK: - Health

    /// Runs on the app's shared 5 s tick: compares playback time with the previous tick.
    func healthTick() {
        guard pendingRebuild == nil, !backoff.isResting else { return }
        let seconds = playbackSeconds
        let sample = HealthSample(
            now: ProcessInfo.processInfo.systemUptime, playbackSeconds: seconds,
            isIntendingToPlay: isIntendingToPlay && video != nil, hasFailed: hasFailed)
        if let cause = monitor.tick(sample) {
            recover(cause: cause.rawValue, detail: stateReport(sinceSeconds: nil).description)
        } else if isIntendingToPlay, let seconds {
            savedSeconds = seconds
        }
    }

    /// Samples playback now and a moment later, logs the state, and rebuilds only if not actually playing.
    func checkAfterWake(cause: String) {
        let earlier = playbackSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            let report = self.stateReport(sinceSeconds: earlier)
            Log.write(cause, "video=\(self.video?.lastPathComponent ?? "none") \(report)")
            let verdict = self.monitor.verdictAfterWake(
                at: ProcessInfo.processInfo.systemUptime, timeAdvanced: report.timeAdvanced,
                isIntendingToPlay: self.isIntendingToPlay && self.video != nil, hasFailed: self.hasFailed)
            if let verdict { self.recover(cause: verdict.rawValue, detail: "on \(cause)") }
        }
    }

    // MARK: - Recovery

    /// Drops the player at once (the Poster shows), then rebuilds after the backoff delay or rests on the Poster.
    func recover(cause: String, detail: String) {
        guard pendingRebuild == nil, !backoff.isResting else { return }
        let name = video?.lastPathComponent ?? "none"
        tearDown()
        guard let delay = backoff.nextDelay() else {
            Log.write("recovery", "cause=\(cause) video=\(name) resting on Poster after "
                + "\(RecoveryBackoff.delays.count) attempts \(detail)")
            return
        }
        Log.write("recovery", "cause=\(cause) video=\(name) position=\(String(format: "%.1f", savedSeconds)) "
            + "rebuild-in=\(Int(delay))s \(detail)")
        let work = DispatchWorkItem { [weak self] in self?.rebuild() }
        pendingRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func rebuild() {
        pendingRebuild = nil
        guard let target = videoProvider() ?? video else {
            Log.write("recovery", "no video to rebuild; staying on Poster")
            return
        }
        let resumeAt = target == video ? savedSeconds : 0
        Log.write("recovery", "rebuilding video=\(target.lastPathComponent) at=\(String(format: "%.1f", resumeAt))")
        show(target, at: resumeAt)
    }

    private func tearDown() {
        observations.forEach { $0.invalidate() }
        observations = []
        looper?.disableLooping()
        looper = nil
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        queuePlayer = nil
        videoLayers.allObjects.forEach { $0.player = nil }
    }
}

// MARK: - Observation and state

extension Player {
    var playbackSeconds: Double? {
        guard let time = queuePlayer?.currentTime(), time.isNumeric else { return nil }
        return time.seconds
    }

    private var hasFailed: Bool {
        guard let queuePlayer else { return false }
        return queuePlayer.status == .failed || queuePlayer.currentItem?.status == .failed
            || looper?.status == .failed
    }

    func stateReport(sinceSeconds earlier: Double?) -> PlayerStateReport {
        guard let queuePlayer else { return .noPlayer }
        let item = queuePlayer.currentItem
        return PlayerStateReport(
            playerStatus: name(of: queuePlayer.status),
            itemStatus: item.map { name(of: $0.status) } ?? "none",
            itemError: (item?.error ?? queuePlayer.error ?? looper?.error).map(describe),
            timeControl: name(of: queuePlayer.timeControlStatus),
            waitingReason: queuePlayer.reasonForWaitingToPlay?.rawValue,
            timeAdvanced: playbackAdvanced(from: earlier, to: playbackSeconds))
    }

    fileprivate func observe(_ player: AVQueuePlayer, _ looper: AVPlayerLooper) {
        let itemStatus = player.observe(\.currentItem?.status, options: [.new]) { [weak self] _, _ in
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
            pendingSeek = nil
            // Seek before playing so a rebuilt player resumes where the old one stopped, not at 0.
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { [weak self, weak player] _ in
                DispatchQueue.main.async {
                    if self?.isIntendingToPlay == true { player?.play() }
                }
            }
        default:
            break
        }
    }

    private func reportFailure(_ what: String) {
        recover(cause: RecoveryCause.failed.rawValue, detail: "\(what) \(stateReport(sinceSeconds: nil))")
    }
}

// MARK: - AV state names

private func name(of status: AVPlayer.Status) -> String {
    switch status {
    case .unknown: return "unknown"
    case .readyToPlay: return "readyToPlay"
    case .failed: return "failed"
    @unknown default: return "rawValue\(status.rawValue)"
    }
}

private func name(of status: AVPlayerItem.Status) -> String {
    switch status {
    case .unknown: return "unknown"
    case .readyToPlay: return "readyToPlay"
    case .failed: return "failed"
    @unknown default: return "rawValue\(status.rawValue)"
    }
}

private func name(of status: AVPlayer.TimeControlStatus) -> String {
    switch status {
    case .paused: return "paused"
    case .waitingToPlayAtSpecifiedRate: return "waitingToPlayAtSpecifiedRate"
    case .playing: return "playing"
    @unknown default: return "rawValue\(status.rawValue)"
    }
}

private func describe(_ error: Error) -> String {
    let nsError = error as NSError
    return "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
}
