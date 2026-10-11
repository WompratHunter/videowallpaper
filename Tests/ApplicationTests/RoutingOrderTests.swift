import Application
import Foundation
import Rotation
import SharedKernel
import TestSupport
import Testing

// MARK: - Routing order
// The coordinator's ordering rules (spec, ADR 0002) that fakes can observe: a Presence change is a switch point acted
// on at once, and the Poster follows every change of video but is never applied once its video has gone.

@MainActor
struct RoutingOrderTests {
    private let dusk = AppHarness.video("dusk.mp4", 0.16)
    private let dawn = AppHarness.video("dawn.mp4", 0.18)

    @Test func aPresenceChangeDecidesAtOnce() {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk, dawn]))
        app.coordinator.launch()
        // Past the Unseen minimum but short of the Visible one: Visible doesn't switch yet.
        app.clock.advance(by: 21 * 60)
        #expect(app.switches.count == 1)

        app.presence.state = .unseen

        // No tick in between: the change itself asked the Rotation.
        #expect(app.switches.count == 2)
        #expect(app.switches.last?.reason == .dwell)
        #expect(app.player.played.count == 2)
    }

    @Test func thePosterFollowsTheVideoAndAStaleOneIsDropped() throws {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk, dawn]))
        app.coordinator.launch()
        let first = try #require(app.player.video)
        let next = first == AppHarness.url(dusk) ? dawn : dusk

        // The Current video is deleted: the Rotation replaces it and the player switches before its Poster arrives.
        app.library.finishAnalysis([next])
        #expect(app.player.video == AppHarness.url(next))

        let stale = URL(fileURLWithPath: "/fake/posters/first.jpg")
        let fresh = URL(fileURLWithPath: "/fake/posters/next.jpg")
        #expect(app.library.deliverPoster(for: first, file: stale) == false)
        #expect(app.library.deliverPoster(for: AppHarness.url(next), file: fresh) == true)
        #expect(app.desktop.posters == [fresh])
    }
}
