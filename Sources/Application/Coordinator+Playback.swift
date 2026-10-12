import Foundation
import Playback

// MARK: - Playback routes
// What Playback hears (screens, session, power, the tick, other contexts' decisions) and where its events go. The
// windows' occlusion is forwarded to the gate and to Presence. Every change of video (Rotation, Recovery or folder
// change) sets its Poster, under the video and as the desktop picture, guarded so a stale Poster is never applied.

extension Coordinator {
    func connectPlayback() {
        playback.videoProvider = { [weak self] in self?.rotationVideoForRebuild() }
        playback.onVideoChange = { [weak self] video in self?.showPoster(for: video) }
        playback.onEvent = { [weak self] event in self?.handle(event) }
        playback.screens.onEvent = { [weak self] event in self?.handle(event) }
        playback.power.onChange = { [weak self] in self?.powerStateChanged() }
    }

    /// Unscreened videos never play, so until the first Analysis the underlay is a still: never black.
    func launchPlayback() {
        let underlay = libraryLaunchUnderlay(toPlay: rotationVideo, desktopPicture: desktopMainScreenPicture())
        if let underlay { playback.setPoster(underlay) }
        playback.apply(.lowPower(isLowPowerMode))
        playback.rebuildWindows()
        playback.start()
    }

    func tickPlayback() {
        playback.reassertWindows()
        playback.healthTick()
    }

    private func handle(_ event: PlaybackEvent) {
        emit(.playback(event))
        guard case let .occlusionChanged(_, isEveryWindowOccluded) = event else { return }
        playback.apply(.allWindowsOccluded(isEveryWindowOccluded))
        notePresenceInput(.everyWindowOccluded(isEveryWindowOccluded), cause: "occlusion")
    }

    private func handle(_ event: ScreenSessionEvent) {
        switch event {
        case .screensDidSleep: screensDidSleep()
        case .screensDidWake: screensDidWake()
        case .systemDidWake: systemDidWake()
        case .sessionDidBecomeActive: sessionDidBecomeActive()
        case .sessionDidResignActive: sessionDidResignActive()
        case .screenParametersChanged: screenParametersChanged()
        }
    }

    private func showPoster(for video: URL) {
        libraryPoster(for: video) { [weak self] poster in
            guard let self, self.playback.video == video else { return false }
            self.playback.setPoster(poster)
            if let file = poster.file { self.desktopSetPoster(file) }
            return true
        }
    }

    // MARK: - Playback commands

    var isLowPowerMode: Bool { playback.isLowPowerMode }

    func playbackPlay(_ video: URL, fade: TimeInterval) {
        playback.play(video, fade: fade)
    }

    /// The folder's set of videos changed: plays the Rotation's Current video, or recovers if its file is gone.
    func playbackFolderChanged(fade: TimeInterval?) {
        playback.folderChanged(toPlay: rotationVideo, fade: fade)
    }

    func playbackVerify(cause: String) {
        playback.verifyPlayback(cause: cause)
    }

    func playbackResetBackoff(on event: RecoveryReset) {
        playback.resetBackoff(on: event)
    }

    // MARK: - System inputs

    package func screensDidSleep() {
        playback.screensDidSleep()
        notePresenceInput(.screensAsleep(true), cause: "screens-sleep")
    }

    package func screensDidWake() {
        playback.reassertWindows()
        playbackResetBackoff(on: .wake)
        playback.apply(.screensAsleep(false))
        notePresenceInput(.screensAsleep(false), cause: "screens-wake")
        playbackVerify(cause: "screens-wake")
    }

    package func systemDidWake() {
        playbackResetBackoff(on: .wake)
        playbackVerify(cause: "wake")
        daylightNoteWake()
    }

    package func sessionDidBecomeActive() {
        notePresenceInput(.sessionInactive(false), cause: "session-active")
        playbackVerify(cause: "session-active")
    }

    package func sessionDidResignActive() {
        notePresenceInput(.sessionInactive(true), cause: "session-inactive")
    }

    package func screenParametersChanged() {
        playback.rebuildWindows()
    }

    package func powerStateChanged() {
        let isOn = playback.lowPowerModeChanged()
        libraryLowPowerModeChanged(isOn)
    }
}
