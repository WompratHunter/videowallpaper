import App
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
// Rotation (pure apart from logging), recording every event and snapshot. As each context ticket swaps its service
// for fakes of its ports, it changes its own lines here.

@MainActor
final class AppHarness {
    static let folder = URL(fileURLWithPath: "/fake/LiveWallpaper", isDirectory: true)

    let clock = FakeClock()
    let settings: FakeSettings
    let library: FakeLibrary
    let rotation = RotationScheduler(directory: folder, dwellScale: 1)
    let player = FakePlayer()
    let windows = FakeWindows()
    let power = FakePower()
    let presence = FakePresence()
    let daylight = FakeDaylight()
    let desktop = FakeDesktop()
    let launchAtLogin = FakeLaunchAtLogin()
    let coordinator: Coordinator
    private(set) var events: [AppEvent] = []
    private(set) var snapshots: [AppSnapshot] = []

    init(library: FakeLibrary, preferences: Preferences = Preferences(modeSetting: "all")) {
        self.library = library
        settings = FakeSettings(preferences)
        rotation.isAutoAppearance = { false }
        coordinator = Coordinator(
            library: library,
            rotation: rotation,
            playback: PlaybackService(player: player, windows: windows, power: power),
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
            guard case .rotation(.switchDecided(_, let to, let reason, let fade, _)) = event else { return nil }
            return DecidedSwitch(to: to, reason: reason, fade: fade)
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
