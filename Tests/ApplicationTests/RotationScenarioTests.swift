import Application
import Foundation
import Rotation
import SharedKernel
import TestSupport
import Testing

// MARK: - Rotation scenarios
// The Rotation through the coordinator, on fakes: when a switch happens, what it looks like, and what the snapshot
// shows of it.

@MainActor
struct RotationScenarioTests {
    private let dusk = AppHarness.video("dusk.mp4", 0.16)
    private let dawn = AppHarness.video("dawn.mp4", 0.18)
    private let fresh = AppHarness.video("fresh.mp4", 0.17)

    @Test func aNewlyAddedVideoPlaysAtTheNextAllowedSwitch() {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk, dawn]))
        app.windows.occlude(true)
        app.coordinator.launch()
        app.clock.advance(by: 60)

        app.library.finishAnalysis([dusk, dawn, fresh])

        // Queued, not played: Dwell is still short of the Unseen minimum.
        #expect(app.switches.count == 1)
        #expect(app.coordinator.snapshot.rotation.statuses[fresh.id] == .queuedAsNew(position: 0))
        app.clock.advance(by: 19 * 60 - 5)
        #expect(app.switches.count == 1)
        app.clock.advance(by: 5)
        #expect(app.switches.last == AppHarness.DecidedSwitch(to: fresh.id, reason: .newVideo, fade: 5))
        #expect(app.player.video == AppHarness.url(fresh))
        #expect(app.coordinator.snapshot.rotation.statuses[fresh.id] == .current)
    }

    @Test func aSwitchWaitsForDwellThenHappensAtTheFirstUnseenMoment() throws {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk, dawn]))
        app.coordinator.launch()
        let first = try #require(app.switches.first?.to)

        // Past the Unseen minimum, short of the Visible one.
        app.clock.advance(by: 25 * 60)
        #expect(app.switches.count == 1)
        #expect(app.coordinator.snapshot.rotation.dwell == 25 * 60)
        #expect(app.coordinator.snapshot.rotation.nextMinimumDwell == TimeInterval(60 * 60))

        app.windows.occlude(true)

        let next = first == dusk.id ? dawn.id : dusk.id
        #expect(app.switches.last == AppHarness.DecidedSwitch(to: next, reason: .dwell, fade: 5))
        #expect(lastDecision(app)?.cause == "visibility")
        #expect(app.player.played.count == 2)
        #expect(app.coordinator.snapshot.rotation.lastSwitch == .dwell)
        #expect(app.coordinator.snapshot.rotation.dwell == 0)
    }

    @Test func aVisibleOnlyHourGivesTheSlowFallback() {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk, dawn]))
        app.coordinator.launch()

        app.clock.advance(by: 60 * 60 - 5)
        #expect(app.switches.count == 1)
        app.clock.advance(by: 5)

        #expect(app.switches.count == 2)
        #expect(app.switches.last?.reason == .visibleFallback)
        #expect(app.switches.last?.fade == 20)
        #expect(app.player.played.count == 2)
    }

    @Test func aDeletedCurrentVideoIsReplacedAtOnce() throws {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk, dawn]))
        app.coordinator.launch()
        let first = try #require(app.switches.first?.to)
        let remaining = first == dusk.id ? dawn : dusk

        app.files.delete(AppHarness.folder.appendingPathComponent(first.fileName))
        app.library.finishAnalysis([remaining])
        // Playback's Recovery rebuilds at once (asynchronously) with the replacement.
        app.playbackClock.advance(by: 0)

        // No tick and no Dwell: the folder change itself replaced it.
        #expect(app.switches.last == AppHarness.DecidedSwitch(to: remaining.id, reason: .currentRemoved, fade: 5))
        #expect(lastDecision(app)?.from == first)
        #expect(app.player.video == AppHarness.url(remaining))
        #expect(app.coordinator.snapshot.rotation.current == remaining.id)
        #expect(app.coordinator.snapshot.rotation.statuses == [remaining.id: .current])
    }

    private func lastDecision(_ app: AppHarness) -> SwitchDecision? {
        app.events.reversed().lazy.compactMap { event -> SwitchDecision? in
            guard case .rotation(.switchDecided(let decision)) = event else { return nil }
            return decision
        }.first
    }
}
