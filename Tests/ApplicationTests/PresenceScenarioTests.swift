import Application
import Presence
import SharedKernel
import TestSupport
import Testing

// MARK: - Presence scenarios
// Presence through the coordinator, on fake lock signal and window list ports: lock and unlock, Veiled once coverage
// holds, and a translucent cover that never hides the wallpaper.

@MainActor
struct PresenceScenarioTests {
    private let dusk = AppHarness.video("dusk.mp4", 0.16)
    private let dawn = AppHarness.video("dawn.mp4", 0.18)

    @Test func lockThenUnlockGivesUnseenThenBack() {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk]))
        app.coordinator.launch()
        #expect(app.lockSignal.isStarted)

        app.lockSignal.lock()
        #expect(app.coordinator.snapshot.presence.current == .unseen)

        app.lockSignal.unlock()
        #expect(app.coordinator.snapshot.presence.current == .visible)
        #expect(presenceChanges(app) == [
            .changed(to: .unseen, because: .input(.locked(true), cause: "lock")),
            .changed(to: .visible, because: .input(.locked(false), cause: "unlock"))
        ])
        #expect(presenceChanges(app).compactMap(\.logLine) == [
            LogLine(cause: "lock", message: "visibility=unseen locked(true)"),
            LogLine(cause: "unlock", message: "visibility=visible locked(false)")
        ])
    }

    @Test func fullCoverageHeldForThirtySecondsGivesVeiled() {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk, dawn]))
        app.coordinator.launch()
        app.windowList.coverEveryScreen()

        // Coverage is sampled only once a switch is near (the Veiled minimum Dwell), then on every tick.
        let launchedAt = app.clock.uptime
        for _ in 0..<(25 * 12) where app.windowList.reads == 0 { app.clock.advance(by: 5) }
        #expect(app.clock.uptime - launchedAt >= 20 * 60)
        app.clock.advance(by: 25)
        #expect(app.coordinator.snapshot.presence.current == .visible)
        app.clock.advance(by: 5)

        #expect(presenceChanges(app) == [.changed(to: .veiled, because: .coverage(1))])
        #expect(app.coordinator.snapshot.presence.current == .veiled)
        // Veiled is a switch point: the Dwell switch happens on that tick, with the quick crossfade.
        #expect(app.switches.count == 2)
        #expect(app.switches.last?.reason == .dwell)
        #expect(app.switches.last?.fade == 5)
    }

    @Test func aTranslucentCoverStaysVisible() {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk, dawn]))
        app.coordinator.launch()

        // A translucent window (e.g. Ghostty) over every screen leaves each window's visible flag set.
        app.windowList.coverEveryScreen()
        app.windows.occlude(false)
        app.clock.advance(by: 10 * 60)

        #expect(app.coordinator.snapshot.presence.current == .visible)
        #expect(presenceChanges(app).isEmpty)
        #expect(app.switches.count == 1)

        // An opaque one clears it, and nobody is watching.
        app.windows.occlude(true)
        #expect(app.coordinator.snapshot.presence.current == .unseen)
    }

    private func presenceChanges(_ app: AppHarness) -> [PresenceEvent] {
        app.events.compactMap { event in
            guard case .presence(let change) = event, case .changed = change else { return nil }
            return change
        }
    }
}
