import Foundation
import SharedKernel

// MARK: - Playback service
// Playback as the coordinator sees it: the shared player, the windows hosting its layers, the Poster underlay,
// crossfades, Recovery and the gate, over its ports. One decoder feeds every display, above a Poster, so tearing the
// player down reveals the Poster, never black. Decisions come from the domain (`Crossfade`, `PlaybackGate`,
// `RecoveryMonitor`, `RecoveryBackoff`, `rebuildPlan`, `folderChangeAction`); this applies them and reports events.

@MainActor
public final class PlaybackService {
    /// Playback's events, on the main queue.
    public var onEvent: (PlaybackEvent) -> Void = { _ in }
    /// Picks the video to play when a rebuild runs (the Rotation's Current video), so a deleted file is replaced.
    public var videoProvider: () -> URL? = { nil }
    /// Called when the player switches to a different video, so its Poster follows.
    public var onVideoChange: (URL) -> Void = { _ in }
    /// Low Power Mode, which the coordinator also hands to the Library and the Rotation.
    public let power: PowerPort
    /// Screen and session notifications, which the coordinator routes to every context that hears them.
    public let screens: ScreenSessionPort

    public internal(set) var video: URL?

    let player: PlayerPort
    let windows: WallpaperWindowsPort
    let clock: PlaybackClock
    let fileExists: (URL) -> Bool

    var gate = PlaybackGate()
    var monitor = RecoveryMonitor()
    var backoff = RecoveryBackoff()
    var pendingRebuild: ScheduledWork?
    var pendingRebuildDelay: TimeInterval = 0
    var isRestingWithoutVideo = false
    var pendingSeek: Double?
    var savedSeconds: Double = 0
    var isEveryWindowOccluded = false
    /// Tells one current player from the next, so a sample or a seek taken on one isn't applied to another.
    var currentToken: Int?
    var lastToken = 0
    var crossfade = Crossfade()
    /// The crossfade's incoming video, while it loads or fades.
    var incoming: (id: Int, video: URL)?

    /// `fileExists` tells a Current video deleted from the folder (Recovery) from one that only left the Rotation.
    public init(
        player: PlayerPort,
        windows: WallpaperWindowsPort,
        power: PowerPort,
        screens: ScreenSessionPort,
        clock: PlaybackClock,
        fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        self.player = player
        self.windows = windows
        self.power = power
        self.screens = screens
        self.clock = clock
        self.fileExists = fileExists
        player.onSignal = { [weak self] signal in self?.handle(signal) }
        windows.onOcclusionChange = { [weak self] change, isEveryWindowOccluded in
            self?.occlusionChanged(change, isEveryWindowOccluded: isEveryWindowOccluded)
        }
    }

    public var slice: PlaybackSlice {
        PlaybackSlice(
            state: gate.state, recovery: recoveryState, video: video.map(videoID),
            isEveryWindowOccluded: isEveryWindowOccluded)
    }

    public var isLowPowerMode: Bool { power.isLowPowerModeEnabled }

    var now: TimeInterval { clock.uptime }

    var shouldBePlaying: Bool { gate.isIntendingToPlay && video != nil }

    // MARK: - Playback

    /// Goes through the rebuild plan so launching in Low Power Mode, or with no video, holds on the Poster.
    public func start() {
        runRebuildPlan(cause: .launch)
    }

    /// Switches to `video` with a crossfade of `fade` seconds; zero, or a player nobody can see, means a cut.
    public func play(_ video: URL, fade: TimeInterval) {
        // A torn-down or recovering player has no outgoing video on screen to fade from, so it cuts too.
        let isPlaying = gate.isIntendingToPlay && player.hasCurrent && !isRecovering
        apply(crossfade.request(video, duration: fade, current: self.video, isPlaying: isPlaying, now: now))
    }

    public func setPoster(_ poster: PosterImage) {
        player.setPoster(poster)
    }

    // MARK: - Windows

    public func rebuildWindows() {
        windows.rebuild()
    }

    public func reassertWindows() {
        windows.reassert()
    }

    // MARK: - Health

    /// Runs on the app's shared 5 s tick: compares playback time with the previous tick.
    public func healthTick() {
        apply(crossfade.tick(now: now))
        guard !isRecovering else { return }
        let sample = HealthSample(
            now: now, playbackSeconds: player.position, isIntendingToPlay: shouldBePlaying,
            hasFailed: player.hasFailed)
        if let cause = monitor.tick(sample) {
            recover(cause: cause, detail: stateReport(sinceSeconds: nil).description)
        } else if gate.isIntendingToPlay {
            savePosition()
        }
    }

    /// Samples playback now and a moment later, reports the state, and rebuilds only if not actually playing.
    public func verifyPlayback(cause: String) {
        let sampledToken = currentToken
        let earlier = player.position
        _ = clock.schedule(after: 1) { [weak self] in
            guard let self else { return }
            let report = self.stateReport(sinceSeconds: earlier)
            self.onEvent(.playerStateReported(cause: cause, video: self.video.map(videoID), report: report))
            // A player swapped in during the sample isn't comparable, and was just rebuilt anyway.
            guard self.currentToken == sampledToken else { return }
            let verdict = self.monitor.verdictAfterWake(
                at: self.now, timeAdvanced: report.timeAdvanced,
                isIntendingToPlay: self.shouldBePlaying, hasFailed: self.player.hasFailed)
            if let verdict { self.recover(cause: verdict, detail: "on \(cause)") }
        }
    }

    func stateReport(sinceSeconds earlier: Double?) -> PlayerStateReport {
        guard player.hasCurrent else { return .noPlayer }
        return player.stateReport(timeAdvanced: playbackAdvanced(from: earlier, to: player.position))
    }

    /// Not while a resume seek is pending: the position is still 0 and would lose the saved one.
    func savePosition() {
        if pendingSeek == nil, let seconds = player.position { savedSeconds = seconds }
    }
}

/// A video's identity is its file name.
func videoID(_ url: URL) -> VideoID {
    VideoID(url.lastPathComponent)
}
