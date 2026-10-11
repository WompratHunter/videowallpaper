import Application
import Library
import Rotation
import SharedKernel
import TestSupport
import Testing

// MARK: - Launch
// Launch through the coordinator, on fakes: settled, analysed videos lead to a first switch, the player is handed the
// Current video and the snapshot names it.

@MainActor
struct LaunchTests {
    private let dusk = AppHarness.video("dusk.mp4", 0.16)
    private let dawn = AppHarness.video("dawn.mp4", 0.18)

    @Test func analysedVideosAtLaunchPlayTheFirstPick() {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk]))
        app.coordinator.launch()

        #expect(app.events == [
            .rotation(.switchDecided(
                from: nil, to: dusk.id, reason: .firstVideo, fade: 5, isDeferred: false))
        ])
        #expect(app.player.played == [AppHarness.url(dusk)])
        #expect(app.coordinator.snapshot.rotation.current == dusk.id)
        #expect(app.snapshots.last == app.coordinator.snapshot)
        #expect(app.coordinator.snapshot.preferences == Preferences(modeSetting: "all"))
        #expect(app.library.isStarted)
        #expect(app.desktop.recordings == 1)
    }

    @Test func analysisFinishingAfterLaunchStartsTheRotation() {
        let app = AppHarness(library: FakeLibrary(pending: ["dusk.mp4"]))
        app.coordinator.launch()
        app.clock.advance(by: 30)
        #expect(app.events.isEmpty)
        #expect(app.player.played.isEmpty)
        #expect(app.coordinator.snapshot.rotation.current == nil)

        app.library.finishAnalysis([dusk])

        // The Library's event comes first (it is the log's cause), then the Rotation's switch it led to.
        #expect(app.events == [
            .library(.eligibleSetChanged(eligible: [dusk], cause: .analysis)),
            .rotation(.switchDecided(from: nil, to: dusk.id, reason: .firstVideo, fade: 5, isDeferred: false))
        ])
        #expect(app.player.played == [AppHarness.url(dusk)])
        #expect(app.coordinator.snapshot.rotation.current == dusk.id)
        #expect(app.coordinator.snapshot.library.eligible == [dusk])
    }

    @Test func theTickSwitchesOnceDwellIsReached() {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk, dawn]))
        app.presence.state = .unseen
        app.coordinator.launch()
        let first = app.switches.first?.to

        app.clock.advance(by: 19 * 60)
        #expect(app.switches.count == 1)
        app.clock.advance(by: 60)

        #expect(app.switches.count == 2)
        let second = app.switches.last
        #expect(second?.reason == .dwell)
        #expect(second?.fade == 5)
        #expect(second?.to != first)
        #expect(app.player.played.count == 2)
        #expect(app.coordinator.snapshot.rotation.current == second?.to)
    }

    @Test func theEligibleSetLineReadsAsBefore() {
        let event = AppEvent.library(.eligibleSetChanged(eligible: [dusk, dawn], cause: .folderChange))
        #expect(event.logLine == LogLine(cause: "folder-change", message: "eligible videos=2"))
        #expect(AppEvent.rotation(.switchDecided(
            from: nil, to: dusk.id, reason: .firstVideo, fade: 5, isDeferred: false)).logLine == nil)
    }
}
