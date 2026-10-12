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

        #expect(app.events.first == .rotation(.modeInEffect(mode: .all, setting: "all", isAutoAppearance: false)))
        #expect(app.events.count == 2)
        #expect(app.switches == [AppHarness.DecidedSwitch(to: dusk.id, reason: .firstVideo, fade: 5)])
        #expect(app.player.played == [AppHarness.url(dusk)])
        #expect(app.coordinator.snapshot.rotation.current == dusk.id)
        #expect(app.snapshots.last == app.coordinator.snapshot)
        #expect(app.coordinator.snapshot.preferences == Preferences(modeSetting: "all"))
        #expect(app.library.isStarted)
    }

    @Test func analysisFinishingAfterLaunchStartsTheRotation() async {
        let app = AppHarness(library: FakeLibrary(pending: ["dusk.mp4"]))
        app.coordinator.launch()
        app.clock.advance(by: 30)
        // Only the Mode in effect, read at launch's decision, and the desktop picture under the window, since
        // nothing is screened yet.
        #expect(app.eventsOutsideLibrary == [
            .rotation(.modeInEffect(mode: .all, setting: "all", isAutoAppearance: false))
        ])
        #expect(app.libraryEvents == [.launchUnderlay(fileName: "earlier.jpg")])
        #expect(app.player.played.isEmpty)
        #expect(app.coordinator.snapshot.rotation.current == nil)

        app.library.analyser.script("dusk.mp4", luminance: 0.16)
        await app.settleLibrary()

        // Analysis, then the eligible set it changed (the log's cause), then the Rotation's switch it led to.
        #expect(app.libraryEvents.count == 3)
        guard case .analysed(dusk.id, version: dusk.version, _) = app.libraryEvents[1] else {
            Issue.record("expected dusk's Analysis, got \(app.libraryEvents)")
            return
        }
        let eligibleAt = app.events.firstIndex(of: .library(.eligibleSetChanged(eligible: [dusk], cause: .analysis)))
        let switchAt = app.events.firstIndex(of: .rotation(.switchDecided(
            from: nil, to: dusk.id, reason: .firstVideo, fade: 5, isDeferred: false)))
        #expect(eligibleAt.map { $0 + 1 } == switchAt)
        #expect(app.switches == [AppHarness.DecidedSwitch(to: dusk.id, reason: .firstVideo, fade: 5)])
        #expect(app.player.played == [AppHarness.url(dusk)])
        #expect(app.coordinator.snapshot.rotation.current == dusk.id)
        #expect(app.coordinator.snapshot.library.eligible == [dusk])
    }

    @Test func theTickSwitchesOnceDwellIsReached() {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk, dawn]))
        app.presence.apply(.everyWindowOccluded(true), cause: "occlusion")
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
    }
}
