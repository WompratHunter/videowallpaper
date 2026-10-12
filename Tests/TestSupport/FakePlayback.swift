import Foundation
import Playback
import SharedKernel

// MARK: - Fake Playback
// Fakes of Playback's ports, for the real Playback service: a scriptable player (ready, failed, stalled, position),
// windows whose occlusion tests set, the power state, screen and session notifications, the video files, and a clock
// that runs Playback's delayed work as the shared fake clock advances.

/// The player as AVFoundation would drive it. While playing and not stalled, its position moves on by a second each
/// time it is sampled; a stalled or paused one stays put.
@MainActor
package final class FakePlayer: PlayerPort {
    package var onSignal: (PlayerSignal) -> Void = { _ in }
    /// The current player's video; nil while only the Poster shows.
    package private(set) var video: URL?
    package private(set) var incoming: (id: Int, video: URL)?
    /// Every video a player was built for, current or incoming, in order.
    package private(set) var played: [URL] = []
    package private(set) var isPlaying = false
    package private(set) var posterCount = 0
    /// A stalled player reports playing but its position never moves.
    package var isStalled = false
    package private(set) var hasFailed = false
    private var seconds: Double = 0

    package init() {}

    package var hasCurrent: Bool { video != nil }

    package var position: Double? {
        guard video != nil else { return nil }
        if isPlaying && !isStalled { seconds += 1 }
        return seconds
    }

    package func stateReport(timeAdvanced: Bool?) -> PlayerStateReport {
        guard video != nil else { return .noPlayer }
        return PlayerStateReport(
            playerStatus: "readyToPlay", itemStatus: hasFailed ? "failed" : "readyToPlay", itemError: nil,
            timeControl: isPlaying ? "playing" : "paused", waitingReason: nil, timeAdvanced: timeAdvanced)
    }

    package func loadCurrent(_ video: URL) {
        self.video = video
        played.append(video)
        isPlaying = false
        hasFailed = false
        seconds = 0
    }

    package func releaseCurrent() {
        video = nil
        isPlaying = false
    }

    package func play() {
        if video != nil { isPlaying = true }
    }

    package func pause() {
        isPlaying = false
    }

    package func seek(to seconds: Double, then: @escaping () -> Void) {
        self.seconds = seconds
        then()
    }

    package func loadIncoming(_ video: URL, id: Int) {
        incoming = (id, video)
        played.append(video)
    }

    package func fadeInIncoming(duration: TimeInterval) {}

    package func promoteIncoming() {
        guard let incoming else { return }
        self.incoming = nil
        video = incoming.video
        seconds = 0
    }

    package func dropIncoming() {
        incoming = nil
    }

    package func setPoster(_ poster: PosterImage) {
        posterCount += 1
    }

    // MARK: - Scripting

    /// The current item became ready to play.
    package func becomeReady() {
        onSignal(.ready)
    }

    /// The current item failed.
    package func fail() {
        hasFailed = true
        onSignal(.failed(.item))
    }

    /// Every window can draw the incoming video.
    package func incomingBecomesReady() {
        guard let incoming else { return }
        onSignal(.incomingReady(id: incoming.id))
    }

    package func incomingFails() {
        guard let incoming else { return }
        onSignal(.incomingFailed(id: incoming.id))
    }
}

@MainActor
package final class FakeWindows: WallpaperWindowsPort {
    package var onOcclusionChange: (OcclusionChange, Bool) -> Void = { _, _ in }
    package private(set) var builds = 0
    private var isOccluded = false

    package init() {}

    /// One window, reported as the real build does.
    package func rebuild() {
        builds += 1
        onOcclusionChange(.windowsBuilt(count: 1), isOccluded)
    }

    package func reassert() {}

    /// Opaque windows cover the one wallpaper window, or uncover it.
    package func occlude(_ isOccluded: Bool) {
        self.isOccluded = isOccluded
        onOcclusionChange(.screen(index: 0, isVisible: !isOccluded), isOccluded)
    }
}

@MainActor
package final class FakePower: PowerPort {
    package private(set) var isLowPowerModeEnabled: Bool
    package var onChange: () -> Void = {}

    package init(isLowPowerModeEnabled: Bool = false) {
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    /// The user turns Low Power Mode on or off; the system posts the change.
    package func setLowPowerMode(_ isOn: Bool) {
        isLowPowerModeEnabled = isOn
        onChange()
    }
}

@MainActor
package final class FakeScreenSession: ScreenSessionPort {
    package var onEvent: (ScreenSessionEvent) -> Void = { _ in }

    package init() {}

    package func post(_ event: ScreenSessionEvent) {
        onEvent(event)
    }
}

/// The video files on disk: every file exists until a test deletes it.
package final class FakeVideoFiles {
    package private(set) var deleted: Set<URL> = []

    package init() {}

    package func delete(_ file: URL) {
        deleted.insert(file)
    }

    package func exists(_ file: URL) -> Bool {
        !deleted.contains(file)
    }
}

/// Playback's delayed work on the shared fake clock. `advance(by:)` steps the clock and runs the ticks and the
/// delayed work falling due on the way, in time order; the fake clock's own `advance(by:)` runs only ticks.
@MainActor
package final class FakePlaybackClock: PlaybackClock {
    private final class Work: ScheduledWork {
        let due: Uptime
        let run: () -> Void
        var isCancelled = false

        init(due: Uptime, run: @escaping () -> Void) {
            self.due = due
            self.run = run
        }

        func cancel() { isCancelled = true }
    }

    private let clock: FakeClock
    private var scheduled: [Work] = []

    package init(_ clock: FakeClock) {
        self.clock = clock
    }

    package var uptime: Uptime { clock.uptime }

    package func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> ScheduledWork {
        let item = Work(due: clock.uptime + delay, run: work)
        scheduled.append(item)
        return item
    }

    package func advance(by seconds: TimeInterval) {
        let end = clock.uptime + seconds
        while let next = nextDue(by: end) {
            clock.advance(by: next.due - clock.uptime)
            scheduled.removeAll { $0 === next }
            if !next.isCancelled { next.run() }
        }
        clock.advance(by: end - clock.uptime)
    }

    /// The earliest work due by `end`, first scheduled first among equals.
    private func nextDue(by end: Uptime) -> Work? {
        scheduled.filter { $0.due <= end }.min { $0.due < $1.due }
    }
}
