import Foundation
import Rotation
import SharedKernel
import Testing

// MARK: - Rotation service tests
// The service on its own: the Mode in effect from the auto-appearance port, events announced once per change, and
// the snapshot slice.

private final class StubAppearance: AutoAppearancePort {
    var isAutoAppearance: Bool

    init(_ isAutoAppearance: Bool) {
        self.isAutoAppearance = isAutoAppearance
    }
}

@MainActor
private final class Harness {
    let appearance: StubAppearance
    let service: RotationService
    var inputs = RotationInputs()
    var now: Uptime = 1_000
    var eligible: [EligibleVideo]
    var presence = Presence.visible
    var modeSetting: String?
    private(set) var events: [RotationEvent] = []

    init(_ eligible: [EligibleVideo], isAutoAppearance: Bool = false, dwellScale: Double = 1) {
        self.eligible = eligible
        appearance = StubAppearance(isAutoAppearance)
        service = RotationService(
            directory: URL(fileURLWithPath: "/fake", isDirectory: true), dwellScale: dwellScale,
            appearance: appearance)
        service.onEvent = { [weak self] event in self?.events.append(event) }
        inputs.uptime = { [weak self] in self?.now ?? 0 }
        inputs.eligibleVideos = { [weak self] in self?.eligible ?? [] }
        inputs.presence = { [weak self] in self?.presence ?? .visible }
        inputs.checkVeil = { [weak self] in self?.presence ?? .visible }
        inputs.modeSetting = { [weak self] in self?.modeSetting }
        service.connect(inputs)
    }

    /// Ticks every 5 s for `seconds`, as the coordinator's tick does.
    func pass(_ seconds: TimeInterval) {
        for _ in 0..<Int(seconds / 5) {
            now += 5
            _ = service.evaluate(cause: "tick")
        }
    }

    var modeEvents: [RotationEvent] {
        events.filter { if case .modeInEffect = $0 { return true } else { return false } }
    }

    var waits: Int {
        events.filter { if case .waitingForUnseen = $0 { return true } else { return false } }.count
    }
}

@MainActor
struct RotationServiceTests {
    private let dark = video("dark.mp4", 0.05)
    private let bright = video("bright.mp4", 0.6)

    @Test func noModeSettingFollowsTheAutoAppearancePort() {
        let auto = Harness([dark], isAutoAppearance: true)
        auto.service.start(present: ["dark.mp4"])
        #expect(auto.modeEvents == [.modeInEffect(mode: .dynamic, setting: nil, isAutoAppearance: true)])

        let fixed = Harness([dark])
        fixed.service.start(present: ["dark.mp4"])
        _ = fixed.service.evaluate(cause: "tick")
        // Announced once, then again only when it changes.
        fixed.modeSetting = "dark"
        _ = fixed.service.evaluate(cause: "tick")
        #expect(fixed.modeEvents == [
            .modeInEffect(mode: .all, setting: nil, isAutoAppearance: false),
            .modeInEffect(mode: .dark, setting: "dark", isAutoAppearance: false)
        ])
    }

    @Test func aDebugDwellScaleIsAnnouncedOnConnecting() {
        let scaled = Harness([dark], dwellScale: 0.01)
        #expect(scaled.events == [.debugDwellScale(0.01)])
        #expect(Harness([dark]).events.isEmpty)
    }

    @Test func waitingForUnseenIsAnnouncedOncePerWait() {
        let app = Harness([dark, bright])
        app.service.start(present: ["dark.mp4", "bright.mp4"])
        // Visible needs an hour; past the Veiled minimum, no video is near enough in brightness to fade to.
        app.pass(21 * 60)
        app.presence = .veiled
        for _ in 0..<3 { _ = app.service.evaluate(cause: "tick") }
        #expect(app.waits == 1)
        #expect(app.service.slice.nextMinimumDwell == TimeInterval(20 * 60))

        app.presence = .unseen
        #expect(app.service.evaluate(cause: "visibility")?.fade == 5)
        #expect(app.service.slice.lastSwitch == .dwell)
        #expect(app.service.slice.dwell == 0)
    }

    @Test func theSliceShowsEachVideosPlaceInThePass() throws {
        let app = Harness([dark])
        app.service.start(present: ["dark.mp4"])
        let first = try #require(app.service.slice.current)
        #expect(app.service.slice.lastSwitch == .firstVideo)
        #expect(app.service.slice.statuses == [first: .current])

        let added = video("added.mp4", 0.06, modified: 100)
        app.eligible = [dark, added]
        app.pass(5 * 60)
        #expect(app.service.refresh(cause: "folder-change") == nil)
        #expect(app.service.slice.statuses == [dark.id: .current, added.id: .queuedAsNew(position: 0)])
        #expect(app.service.slice.dwell == 5 * 60)
        #expect(app.service.slice.nextMinimumDwell == TimeInterval(60 * 60))
    }
}
