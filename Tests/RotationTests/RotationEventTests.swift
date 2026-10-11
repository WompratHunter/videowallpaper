import Rotation
import SharedKernel
import Testing

// MARK: - Rotation event tests
// The Rotation suites move here from CoreTests with ticket 08.

@Test func aSwitchIsNotLoggedFromItsEventYet() {
    let event = RotationEvent.switchDecided(
        from: nil, to: VideoID("rain.mp4"), reason: .firstVideo, fade: 5, isDeferred: false)
    // Until ticket 08 moves the line here, the scheduler writes it; logging it here too would double it.
    #expect(event.logLine == nil)
}

@Test(arguments: [(SwitchReason.firstVideo, "first-video"), (.visibleFallback, "visible-fallback")])
func switchReasonsLogAsBefore(reason: SwitchReason, logged: String) {
    #expect(reason.rawValue == logged)
}
