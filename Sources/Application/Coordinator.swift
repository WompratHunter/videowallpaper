import Daylight
import Desktop
import Foundation
import Library
import Playback
import Presence
import Rotation
import SharedKernel

// MARK: - Coordinator
// The only place contexts meet (ADR 0002): it hears each context's events and the system's inputs, and calls other
// contexts' commands, with the order written out. Each context's routes live in `Coordinator+<Context>.swift`: what
// that context hears, and the commands the other routes issue to it, so a context's ticket edits its own file. This
// file holds what runs every context in order (launch and the tick), the event stream and the snapshot. It imports
// every context already, so a context's service can move into its target under the same name (`<Context>Service`)
// without an edit here.

@MainActor
public final class Coordinator {
    /// The shared tick: window level, player health and Rotation decisions.
    static let tickInterval: TimeInterval = 5
    static let tickTolerance: TimeInterval = 2

    public private(set) var snapshot = AppSnapshot()

    let library: LibraryService
    let rotation: RotationService
    let playback: PlaybackService
    let presence: PresenceService
    let daylight: DaylightService
    let desktop: DesktopService
    let clock: ClockPort
    let settings: SettingsPort

    private var subscribers: [(AppEvent) -> Void] = []
    private var snapshotObservers: [(AppSnapshot) -> Void] = []
    private var pendingEvents: [AppEvent] = []
    private var isDelivering = false

    package init(
        library: LibraryService,
        rotation: RotationService,
        playback: PlaybackService,
        presence: PresenceService,
        daylight: DaylightService,
        desktop: DesktopService,
        clock: ClockPort,
        settings: SettingsPort
    ) {
        self.library = library
        self.rotation = rotation
        self.playback = playback
        self.presence = presence
        self.daylight = daylight
        self.desktop = desktop
        self.clock = clock
        self.settings = settings
    }

    /// Every event from now on, in order, on the main actor.
    public func subscribe(_ subscriber: @escaping (AppEvent) -> Void) {
        subscribers.append(subscriber)
    }

    /// Called with the new snapshot whenever it changes.
    public func observeSnapshot(_ observer: @escaping (AppSnapshot) -> Void) {
        snapshotObservers.append(observer)
    }

    // MARK: - Launch and tick

    /// Once, at launch. Settled videos are known before the first pick and its saved Poster; Low Power Mode is known
    /// before any Analysis starts or player is built.
    package func launch() {
        connectLibrary()
        connectRotation()
        connectPlayback()
        connectPresence()
        // The folder's videos now join the Rotation as their Analysis finishes, without counting as newly added.
        let present = libraryVideoNames
        launchDesktop()
        launchLibrary()
        launchRotation(present: present)
        launchPlayback()
        clock.startTicking(every: Self.tickInterval, tolerance: Self.tickTolerance) { [weak self] in self?.tick() }
        playbackVerify(cause: "launch")
        publishSnapshot()
    }

    private func tick() {
        tickPlayback()
        evaluateRotation(cause: "tick")
        // Preferences are read at decision time, so an external `defaults write` shows here by the next tick.
        publishSnapshot()
    }

    // MARK: - Events and snapshot

    /// Delivers `event` to every subscriber, after any still being delivered, so subscribers see the order it
    /// happened in. Call it before routing the event on, so the log reads cause before effect.
    func emit(_ event: AppEvent) {
        pendingEvents.append(event)
        guard !isDelivering else { return }
        isDelivering = true
        while !pendingEvents.isEmpty {
            let next = pendingEvents.removeFirst()
            subscribers.forEach { $0(next) }
        }
        isDelivering = false
        publishSnapshot()
    }

    func publishSnapshot() {
        let next = AppSnapshot(
            library: library.slice,
            rotation: rotation.slice,
            playback: playback.slice,
            presence: presence.slice,
            daylight: daylight.slice,
            desktop: desktop.slice,
            preferences: settings.load())
        guard next != snapshot else { return }
        snapshot = next
        snapshotObservers.forEach { $0(next) }
    }
}
