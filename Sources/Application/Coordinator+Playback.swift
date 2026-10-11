import Core // Legacy: Crossfade and RecoveryBackoff, until ticket 07 moves them into Playback
import Foundation

// MARK: - Playback routes
// What the player and windows hear (screens, session, power, the tick, other contexts' decisions) and where their
// callbacks go. Every change of video (Rotation, Recovery or folder change) sets its Poster, under the video and as
// the desktop picture, guarded so a stale Poster is never applied.

extension Coordinator {
    func connectPlayback() {
        playback.player.videoProvider = { [weak self] in self?.rotationVideoForRebuild() }
        playback.player.onVideoChange = { [weak self] video in self?.showPoster(for: video) }
        playback.windows.onOcclusionChange = { [weak self] isAllOccluded in
            self?.playback.player.apply(.allWindowsOccluded(isAllOccluded))
            self?.notePresenceInput(.everyWindowOccluded(isAllOccluded), cause: "occlusion")
        }
    }

    /// Unscreened videos never play, so until the first Analysis the underlay is a still: never black.
    func launchPlayback() {
        let underlay = libraryLaunchUnderlay(toPlay: rotationVideo, desktopPicture: desktopMainScreenPicture())
        if let underlay { playback.player.setPoster(underlay) }
        playback.player.apply(.lowPower(isLowPowerMode))
        playback.windows.rebuild()
        playback.player.start()
    }

    func tickPlayback() {
        playback.windows.reassert()
        playback.player.healthTick()
    }

    private func showPoster(for video: URL) {
        libraryPoster(for: video) { [weak self] poster in
            guard let self, self.playback.player.video == video else { return false }
            self.playback.player.setPoster(poster)
            if let file = poster.file { self.desktopSetPoster(file) }
            return true
        }
    }

    // MARK: - Playback commands

    var isLowPowerMode: Bool { playback.power.isLowPowerModeEnabled }

    func playbackPlay(_ video: URL, fade: TimeInterval) {
        playback.player.play(video, fade: fade)
    }

    /// The folder's set of videos changed: plays the Rotation's Current video, or recovers if its file is gone.
    func playbackFolderChanged(fade: TimeInterval?) {
        playback.player.folderChanged(toPlay: rotationVideo, fade: fade ?? Crossfade.quickDuration)
    }

    func playbackVerify(cause: String) {
        playback.player.verifyPlayback(cause: cause)
    }

    func playbackResetBackoff(on event: RecoveryBackoff.ResetEvent) {
        playback.player.resetBackoff(on: event)
    }

    // MARK: - System inputs

    package func screensDidSleep() {
        playback.player.apply(.screensAsleep(true))
        notePresenceInput(.screensAsleep(true), cause: "screens-sleep")
    }

    package func screensDidWake() {
        playback.windows.reassert()
        playbackResetBackoff(on: .wake)
        playback.player.apply(.screensAsleep(false))
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
        playback.windows.rebuild()
    }

    package func powerStateChanged() {
        let isOn = isLowPowerMode
        playback.player.apply(.lowPower(isOn))
        libraryLowPowerModeChanged(isOn)
    }
}
