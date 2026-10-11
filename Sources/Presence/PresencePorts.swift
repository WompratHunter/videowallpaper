import Foundation

// MARK: - Presence ports
// The system signals Presence reads, each behind a port so tests use fakes and the App Store phase can swap adapters.
// Today's adapters are in `Adapters/`; Platform builds them.

/// Whether the screen is locked, as the system announces it.
///
/// Today's adapter (`DistributedLockSignal`) listens for the distributed screen lock and unlock notifications, which
/// are undocumented. The documented public fallback, should they ever stop arriving, is the screens sleep/wake and
/// session active/inactive notifications, which reach Presence as their own inputs: a locked Mac whose screens sleep
/// or whose session is switched away is still Unseen, and their wake and active events verify playback as unlock does.
@MainActor
public protocol LockSignalPort: AnyObject {
    /// Called on the main actor: true on lock, false on unlock.
    var onChange: (Bool) -> Void { get set }
    /// Starts listening, for the app's lifetime. Called once.
    func start()
}

/// The system window list, reduced to what is readable without Screen Recording permission.
@MainActor
public protocol WindowListPort: AnyObject {
    /// Every on-screen window, or nil when the list can't be read.
    func windows() -> [ListedWindow]?
    /// Every display's bounds, in the window list's coordinate space.
    func screens() -> [ScreenRect]
}

/// The wall clock and one pending timer, for the coverage clock and its expiry.
@MainActor
public protocol PresenceClockPort: AnyObject {
    var now: Date { get }
    /// Runs `work` once on the main actor `delay` seconds from now, replacing any call still pending.
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void)
}
