import Application
import Daylight
import Desktop
import Foundation
import Library
import Playback
import Presence
import Rotation
import SharedKernel
import TestSupport

// MARK: - App harness
// The whole app on fakes: one coordinator with a fake clock and settings, a fake per context service and the real
// Rotation (on a fake appearance flag), recording every event and snapshot. As each context ticket swaps its service
// for fakes of its ports, it changes its own lines here.

@MainActor
final class AppHarness {
    static let folder = URL(fileURLWithPath: "/fake/LiveWallpaper", isDirectory: true)

    let clock = FakeClock()
    let settings: FakeSettings
    let library: FakeLibrary
    let appearance = FakeAutoAppearance()
    let rotation: RotationService
    let player = FakePlayer()
    let windows = FakeWindows()
    let power = FakePower()
    let screens = FakeScreenSession()
    let files = FakeVideoFiles()
    let playbackClock: FakePlaybackClock
    let lockSignal = FakeLockSignal()
    let windowList = FakeWindowList()
    let presenceClock: FakePresenceClock
    let presence: PresenceService
    let daylight = FakeDaylight()
    let desktop = FakeDesktop()
    let launchAtLogin = FakeLaunchAtLogin()
    let coordinator: Coordinator
    private(set) var events: [AppEvent] = []
    private(set) var snapshots: [AppSnapshot] = []

    init(library: FakeLibrary, preferences: Preferences = Preferences(modeSetting: "all")) {
        self.library = library
        settings = FakeSettings(preferences)
        playbackClock = FakePlaybackClock(clock)
        rotation = RotationService(directory: Self.folder, appearance: appearance)
        presenceClock = FakePresenceClock { [clock] in clock.now }
        presence = PresenceService(lockSignal: lockSignal, windowList: windowList, clock: presenceClock)
        coordinator = Coordinator(
            library: library,
            rotation: rotation,
            playback: PlaybackService(
                player: player, windows: windows, power: power, screens: screens, clock: playbackClock,
                fileExists: files.exists),
            presence: presence,
            daylight: daylight.service { [clock] in clock.now },
            desktop: desktop.service,
            launchAtLogin: launchAtLogin,
            clock: clock,
            settings: settings)
        coordinator.subscribe { [weak self] event in self?.events.append(event) }
        coordinator.observeSnapshot { [weak self] snapshot in self?.snapshots.append(snapshot) }
    }

    struct DecidedSwitch: Equatable {
        let to: VideoID
        let reason: SwitchReason
        let fade: TimeInterval
    }

    /// The switches decided so far, in order.
    var switches: [DecidedSwitch] {
        events.compactMap { event in
            guard case .rotation(.switchDecided(let decision)) = event else { return nil }
            return DecidedSwitch(to: decision.to, reason: decision.reason, fade: decision.fade)
        }
    }

    /// Every event but Playback's own, for tests about the other contexts.
    var eventsBesidesPlayback: [AppEvent] {
        events.filter { event in
            if case .playback = event { return false }
            return true
        }
    }

    /// Playback's events so far, in order.
    var playbackEvents: [PlaybackEvent] {
        events.compactMap { event in
            guard case .playback(let playbackEvent) = event else { return nil }
            return playbackEvent
        }
    }

    static func video(_ name: String, _ luminance: Double) -> EligibleVideo {
        EligibleVideo(
            id: VideoID(name), version: Version(size: 1_000, modifiedMilliseconds: 1_700_000_000_000),
            meanLuminance: luminance)
    }

    static func url(_ video: EligibleVideo) -> URL {
        folder.appendingPathComponent(video.name)
    }
}
