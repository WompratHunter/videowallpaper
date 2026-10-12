import Application
import Foundation
@testable import Library
import Rotation
import SharedKernel
import TestSupport
import Testing

// MARK: - Library scenarios
// The Library on fakes of its ports, through the coordinator: a copied file waits until it settles, is analysed, then
// joins the Rotation and plays next; an over-limit Video is Excluded until overridden; a replaced Version is analysed
// again and keeps its override; a rename is a new Video; Low Power Mode cancels Analysis and re-queues it.

@MainActor
struct LibraryScenarioTests {
    private let dusk = AppHarness.video("dusk.mp4", 0.16)
    private let dawn = AppHarness.video("dawn.mp4", 0.18)
    private let strobe = VideoID("strobe.mp4")

    @Test func aCopiedFileIsIgnoredUntilSettledThenAnalysedAndPlayedNext() async {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk]))
        app.presence.apply(.everyWindowOccluded(true), cause: "occlusion")
        app.coordinator.launch()
        app.library.folder.passSettleInterval()
        app.library.analyser.script("dawn.mp4", luminance: 0.18)

        app.library.folder.write("dawn.mp4", size: 100)
        #expect(app.status(of: dawn.id) == .settling)
        app.library.folder.write("dawn.mp4", size: 200)
        app.library.folder.passSettleInterval()
        await app.settleLibrary()
        // Still growing at the check: neither analysed nor eligible.
        #expect(app.library.analyser.measured.isEmpty)
        #expect(app.coordinator.snapshot.library.eligible == [dusk])

        app.library.folder.passSettleInterval()
        #expect(app.libraryEvents.last == .settled(videos: [dawn.id, dusk.id]))
        #expect(app.coordinator.snapshot.library.videos.map(\.status) == [.analysing, .eligible])
        await app.settleLibrary()

        #expect(app.library.analyser.measured == ["dawn.mp4"])
        #expect(app.coordinator.snapshot.library.eligible.map(\.id) == [dawn.id, dusk.id])
        #expect(app.status(of: dawn.id) == .eligible)
        #expect(app.libraryEvents.suffix(2).map(\.logLine?.cause) == ["analysis", "analysis"])
        app.clock.advance(by: 20 * 60)
        #expect(app.switches.last?.to == dawn.id)
        #expect(app.switches.last?.reason == .newVideo)
        #expect(app.player.video == AppHarness.url(dawn))
    }

    @Test func anOverLimitVideoIsExcludedUntilOverridden() async {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk], pending: ["strobe.mp4"]))
        app.library.analyser.script("strobe.mp4", luminance: 0.5, flashesPerSecond: 6)
        app.coordinator.launch()
        await app.settleLibrary()

        #expect(app.libraryEvents.contains(.excluded(strobe, flashesPerSecond: 6)))
        #expect(app.coordinator.snapshot.library.eligible == [dusk])
        #expect(app.status(of: strobe) == .excluded(flashesPerSecond: 6))
        app.library.folder.passSettleInterval()

        // As today, an override applies at the Library's next decision: here, a new Video settling.
        app.settings.stored.flashOverrides = ["strobe.mp4"]
        app.library.analyser.script("dawn.mp4", luminance: 0.18)
        app.library.folder.write("dawn.mp4", size: 100)
        app.library.folder.passSettleInterval()
        #expect(app.libraryEvents.contains(.overridden(strobe, flashesPerSecond: 6)))
        #expect(app.status(of: strobe) == .overridden(flashesPerSecond: 6))
        #expect(app.coordinator.snapshot.library.eligible.map(\.id) == [dusk.id, strobe])
    }

    @Test func aReplacedVersionIsAnalysedAgainAndKeepsItsOverride() async throws {
        let app = AppHarness(
            library: FakeLibrary(eligible: [dusk], pending: ["strobe.mp4"]),
            preferences: Preferences(modeSetting: "all", flashOverrides: ["strobe.mp4"]))
        app.library.analyser.script("strobe.mp4", luminance: 0.5, flashesPerSecond: 6)
        app.coordinator.launch()
        await app.settleLibrary()
        let first = try #require(app.coordinator.snapshot.library.videos.first { $0.id == strobe })
        #expect(first.status == .overridden(flashesPerSecond: 6))
        app.library.folder.passSettleInterval()

        app.library.folder.write("strobe.mp4", size: 2_000)
        app.library.folder.passSettleInterval()
        // The new Version has no Analysis yet: it leaves the Rotation until it is screened.
        #expect(app.status(of: strobe) == .analysing)
        #expect(app.coordinator.snapshot.library.eligible == [dusk])
        await app.settleLibrary()

        #expect(app.library.analyser.measured == ["strobe.mp4", "strobe.mp4"])
        let replaced = try #require(app.coordinator.snapshot.library.videos.first { $0.id == strobe })
        #expect(replaced.version.size == 2_000)
        #expect(replaced.status == .overridden(flashesPerSecond: 6))
        #expect(app.coordinator.snapshot.library.eligible.last?.version == replaced.version)
    }

    @Test func aRenameIsANewVideo() async throws {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk, dawn]))
        app.presence.apply(.everyWindowOccluded(true), cause: "occlusion")
        app.coordinator.launch()
        let current = try #require(app.player.video?.lastPathComponent)
        let other = current == dusk.name ? dawn.name : dusk.name
        app.library.analyser.script("sunrise.mp4", luminance: 0.2)
        app.library.folder.passSettleInterval()

        app.library.folder.rename(other, to: "sunrise.mp4")
        app.library.folder.passSettleInterval()
        await app.settleLibrary()

        // Analysis belongs to a Version of a Video, so the new name is analysed again.
        #expect(app.library.analyser.measured == ["sunrise.mp4"])
        #expect(app.coordinator.snapshot.library.videos.map(\.id.fileName) == [current, "sunrise.mp4"].sorted())
        app.clock.advance(by: 20 * 60)
        #expect(app.switches.last?.to == VideoID("sunrise.mp4"))
        #expect(app.switches.last?.reason == .newVideo)
    }

    @Test func aFailedAnalysisIsReportedAndTheVideoDoesNotPlay() async {
        let app = AppHarness(library: FakeLibrary(pending: ["broken.mp4"]))
        app.library.analyser.script("broken.mp4", .fails)
        app.coordinator.launch()
        await app.settleLibrary()

        #expect(app.libraryEvents.last == .analysisFailed(VideoID("broken.mp4"), reason: "scripted failure"))
        #expect(
            app.libraryEvents.last?.logLine?.message == "video=broken.mp4 failed: scripted failure; it will not play")
        #expect(app.status(of: VideoID("broken.mp4")) == .analysisFailed)
        #expect(app.player.played.isEmpty)
    }

    @Test func lowPowerModeCancelsAnalysisAndRequeuesIt() async {
        let app = AppHarness(library: FakeLibrary(pending: ["dusk.mp4"]))
        app.coordinator.launch()
        app.power.isLowPowerModeEnabled = true
        app.coordinator.powerStateChanged()
        // Scripted only now: the cancelled run must not finish as an Analysis.
        app.library.analyser.script("dusk.mp4", luminance: 0.16)
        await app.settleLibrary()

        #expect(app.libraryEvents.last == .analysisPaused(dusk.id))
        #expect(app.status(of: dusk.id) == .analysing)
        #expect(app.player.played.isEmpty)

        app.power.isLowPowerModeEnabled = false
        app.coordinator.powerStateChanged()
        await app.settleLibrary()

        #expect(app.library.analyser.measured == ["dusk.mp4", "dusk.mp4"])
        #expect(app.coordinator.snapshot.library.eligible.map(\.id) == [dusk.id])
        #expect(app.player.played == [AppHarness.url(dusk)])
    }
}

// MARK: - Harness helpers

extension AppHarness {
    /// Lets the Library's work off the main actor finish: every Poster read or export, and Analysis unless it waits for
    /// the analyser's script.
    func settleLibrary() async {
        let service = library.service
        while true {
            var work = Array(service.posterWork.values)
            if let job = service.analyses.job, let running = service.analyses.running,
               library.analyser.isScripted(running.name) {
                work.append(job)
            }
            guard !work.isEmpty else { return }
            for task in work { await task.value }
        }
    }

    /// Every event but the Library's, for tests that don't follow the Library (its launch underlay line among them).
    var eventsOutsideLibrary: [AppEvent] {
        events.filter { event in
            guard case .library = event else { return true }
            return false
        }
    }

    var libraryEvents: [LibraryEvent] {
        events.compactMap { event in
            guard case .library(let library) = event else { return nil }
            return library
        }
    }

    /// The Video's catalogue status as the Library has it now (the snapshot shows it from the next event or tick).
    func status(of video: VideoID) -> CatalogueStatus? {
        library.service.slice.videos.first { $0.id == video }?.status
    }
}
