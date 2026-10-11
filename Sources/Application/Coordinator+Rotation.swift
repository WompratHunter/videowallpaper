import Foundation
import Rotation

// MARK: - Rotation routes
// What a Rotation decision reads (time, eligible videos, Presence, Low Power Mode, the Mode setting, Daylight), when
// it decides (launch, the tick, a Presence change, a folder change, a rebuild) and where a switch goes.

extension Coordinator {
    func connectRotation() {
        var inputs = RotationInputs()
        inputs.uptime = { [clock] in clock.uptime }
        inputs.eligibleVideos = { [weak self] in self?.eligibleVideos ?? [] }
        inputs.presence = { [weak self] in self?.currentPresence ?? .visible }
        inputs.checkVeil = { [weak self] in self?.sampleVeil() ?? .visible }
        inputs.isPowerSaving = { [weak self] in self?.isLowPowerMode ?? false }
        inputs.modeSetting = { [settings] in settings.load().modeSetting }
        inputs.daylight = { [weak self] in self?.daylightForRotation() ?? (0, "none") }
        rotation.connect(inputs)
        rotation.onEvent = { [weak self] event in self?.emit(.rotation(event)) }
    }

    func launchRotation(present: Set<String>) {
        rotation.start(present: present)
    }

    // MARK: - Rotation commands

    /// The Current video, for the player to build or play.
    var rotationVideo: URL? { rotation.video }

    /// On the tick and on a Presence change: a switch the moment allows plays at once.
    func evaluateRotation(cause: String) {
        guard let next = rotation.evaluate(cause: cause) else { return }
        playbackPlay(next.video, fade: next.fade)
    }

    /// The eligible set changed: returns the fade of the switch it led to, if any.
    func rotationFolderChanged() -> TimeInterval? {
        rotation.refresh(cause: "folder-change")?.fade
    }

    /// A rebuild asks what to play, so a deleted Current video is replaced first.
    func rotationVideoForRebuild() -> URL? {
        _ = rotation.refresh(cause: "rebuild")
        return rotation.video
    }

    func rotationAwayFromDesk(_ event: AwayFromDesk) {
        rotation.apply(event)
    }
}
