import Foundation
import Rotation
import SharedKernel
import Testing

// MARK: - Rotation event tests
// Each event renders the line the scheduler wrote before it moved onto events, character for character.

private func decision(
    from: String? = "lucyna.mp4",
    reason: SwitchReason = .dwell,
    isDeferred: Bool = false,
    deltaL: Double? = 0.016,
    target: TargetBrightness? = nil
) -> SwitchDecision {
    SwitchDecision(
        from: from.map(VideoID.init), to: VideoID("maomao.mp4"), reason: reason, fade: 5, isDeferred: isDeferred,
        cause: "tick", deltaL: deltaL, presence: .veiled, mode: .all, target: target, dwell: 20 * 60 + 59)
}

@Test func aSwitchLogsAsBefore() {
    #expect(RotationEvent.switchDecided(decision()).logLine == LogLine(
        cause: "rotation",
        message: "switch reason=dwell on=tick from=lucyna.mp4 to=maomao.mp4 ΔL=0.016 fade=5s visibility=veiled "
            + "mode=all dwell=20m"))
}

@Test func theFirstSwitchInLowPowerModeLogsAsBefore() {
    let first = decision(from: nil, reason: .firstVideo, isDeferred: true, deltaL: nil)
    #expect(RotationEvent.switchDecided(first).logLine.message
        == "switch reason=first-video on=tick from=none to=maomao.mp4 ΔL=n/a fade=5s visibility=veiled mode=all "
            + "dwell=20m (Low Power Mode: plays when it ends)")
}

@Test func aSwitchAimedAtDaylightLogsItsTarget() {
    let aimed = decision(target: TargetBrightness(daylight: 0.25, pickRank: 1.0 / 3, daylightSource: "fix"))
    #expect(RotationEvent.switchDecided(aimed).logLine.message
        == "switch reason=dwell on=tick from=lucyna.mp4 to=maomao.mp4 ΔL=0.016 fade=5s visibility=veiled mode=all "
            + "daylight=0.25 target=0.25 to-rank=0.33 daylight-source=fix dwell=20m")
}

@Test func waitingModeAndDebugLinesLogAsBefore() {
    #expect(RotationEvent.waitingForUnseen(presence: .veiled).logLine == LogLine(
        cause: "rotation",
        message: "switch due but no allowed video within ΔL 0.08: waiting for Unseen (visibility=veiled)"))
    #expect(RotationEvent.modeInEffect(mode: .dynamic, setting: nil, isAutoAppearance: true).logLine.message
        == "mode=dynamic setting=none auto-appearance=yes")
    #expect(RotationEvent.modeInEffect(mode: .dark, setting: "Dark", isAutoAppearance: false).logLine.message
        == "mode=dark setting=Dark auto-appearance=no")
    #expect(RotationEvent.debugDwellScale(0.01).logLine
        == LogLine(cause: "rotation", message: "debug Dwell scale=0.01"))
}

@Test(arguments: [(SwitchReason.firstVideo, "first-video"), (.visibleFallback, "visible-fallback")])
func switchReasonsLogAsBefore(reason: SwitchReason, logged: String) {
    #expect(reason.rawValue == logged)
}
