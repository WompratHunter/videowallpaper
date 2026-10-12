import Application
import Foundation
import Playback
import SharedKernel
import TestSupport
import Testing

// MARK: - Playback scenarios
// Playback through the coordinator, on fakes of its ports: Low Power Mode during a crossfade, Recovery's backoff, and
// occlusion pausing without counting as stuck.

@MainActor
struct PlaybackScenarioTests {
    private let dusk = AppHarness.video("dusk.mp4", 0.16)
    private let dawn = AppHarness.video("dawn.mp4", 0.18)
    private let noon = AppHarness.video("noon.mp4", 0.17)

    private var recoveryEvents: (AppHarness) -> [RecoveryEvent] {
        { app in
            app.playbackEvents.compactMap { event in
                guard case .recovery(let recovery) = event else { return nil }
                return recovery
            }
        }
    }

    @Test func currentVideoDeletedMidCrossfadeInLowPowerModeEndsOnThePosterThenPlaysTheReplacement() throws {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk, dawn, noon]))
        app.presence.state = .unseen
        app.coordinator.launch()
        let first = try #require(app.player.video)
        // Past the Unseen minimum Dwell: the next tick switches with a crossfade, which starts loading.
        app.playbackClock.advance(by: 20 * 60 + 5)
        let incoming = try #require(app.player.incoming?.video)
        #expect(incoming != first)
        app.player.incomingBecomesReady()

        // Low Power Mode mid-fade: both players go, only the Poster shows.
        app.power.setLowPowerMode(true)
        #expect(app.player.video == nil)
        #expect(app.player.incoming == nil)
        #expect(app.coordinator.snapshot.playback.state == .posterOnly)

        // The Rotation's Current video (the one fading in) is deleted: nothing is built in Low Power Mode.
        app.files.delete(incoming)
        app.library.finishAnalysis([dusk, dawn, noon].filter { AppHarness.url($0) != incoming })
        app.playbackClock.advance(by: 30)
        #expect(app.player.video == nil)
        #expect(app.playbackEvents.contains(.recovery(.folderChangeHeldForPower)))
        let replacement = try #require(app.coordinator.snapshot.rotation.current)
        #expect(replacement.fileName != incoming.lastPathComponent)

        app.power.setLowPowerMode(false)

        #expect(app.player.video?.lastPathComponent == replacement.fileName)
        #expect(app.player.isPlaying)
        #expect(app.coordinator.snapshot.playback.state == .playing)
        #expect(app.coordinator.snapshot.playback.video == replacement)
        #expect(app.events.contains(.playback(.lowPowerModeChanged(isOn: false))))
    }

    @Test func aStalledPlayerRecoversWithBackoffRestsThenRetriesOnWake() throws {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk]))
        app.coordinator.launch()
        let video = try #require(app.player.video)
        app.player.isStalled = true

        // Past the rebuild's grace, two frozen ticks call it stuck; each rebuild stalls again.
        app.playbackClock.advance(by: 30)
        #expect(app.coordinator.snapshot.playback.recovery == .rebuilding(in: 10))
        #expect(app.player.video == nil)
        app.playbackClock.advance(by: 10 + 30)
        #expect(app.coordinator.snapshot.playback.recovery == .rebuilding(in: 60))
        app.playbackClock.advance(by: 60 + 30)
        #expect(app.coordinator.snapshot.playback.recovery == .rebuilding(in: 300))
        app.playbackClock.advance(by: 300 + 30)

        #expect(app.coordinator.snapshot.playback.recovery == .resting)
        #expect(app.player.video == nil)
        let scheduled = recoveryEvents(app).compactMap { event -> TimeInterval? in
            guard case let .scheduled(.stuck, _, _, delay, _) = event else { return nil }
            return delay
        }
        #expect(scheduled == [10, 60, 300])
        let rests = recoveryEvents(app).filter { if case .resting(.stuck, _, 3, _) = $0 { true } else { false } }
        #expect(rests.count == 1)
        // Resting is quiet: no further attempt however long it waits.
        app.playbackClock.advance(by: 3_600)
        #expect(app.player.played.count == 4)

        app.player.isStalled = false
        app.screens.post(.systemDidWake)
        let retry = try #require(recoveryEvents(app).last)
        let line = try #require(PlaybackEvent.recovery(retry).logLine?.message)
        #expect(line.hasPrefix("cause=retry-after-rest video=\(video.lastPathComponent) position="))
        #expect(line.hasSuffix(" rebuild-in=10s on wake"))
        app.playbackClock.advance(by: 10)
        #expect(app.player.video == video)
        // The same video resumes at its saved position: it plays once the item is ready and the seek is done.
        #expect(!app.player.isPlaying)
        app.player.becomeReady()
        #expect(app.player.isPlaying)
        #expect(app.coordinator.snapshot.playback.recovery == .idle)
        app.playbackClock.advance(by: 60)
        #expect(app.coordinator.snapshot.playback.recovery == .idle)
    }

    @Test func everyWindowOccludedPausesAndIsNotCountedAsStuck() throws {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk]))
        app.coordinator.launch()
        _ = try #require(app.player.video)
        #expect(app.player.isPlaying)

        app.windows.occlude(true)

        #expect(!app.player.isPlaying)
        #expect(app.coordinator.snapshot.playback.state == .paused)
        #expect(app.coordinator.snapshot.playback.isEveryWindowOccluded)
        #expect(app.events.suffix(2) == [
            .playback(.occlusionChanged(.screen(index: 0, isVisible: false), isEveryWindowOccluded: true)),
            .playback(.stateChanged(
                input: .allWindowsOccluded(true), action: .pause, state: .paused, video: dusk.id))
        ])
        // A paused player's frozen time is expected: no Recovery however long it stays covered.
        app.playbackClock.advance(by: 10 * 60)
        #expect(!recoveryEvents(app).contains { if case .scheduled = $0 { true } else { false } })
        #expect(app.coordinator.snapshot.playback.recovery == .idle)

        app.windows.occlude(false)
        #expect(app.player.isPlaying)
        #expect(app.coordinator.snapshot.playback.state == .playing)
        app.playbackClock.advance(by: 60)
        #expect(app.coordinator.snapshot.playback.recovery == .idle)
    }
}
