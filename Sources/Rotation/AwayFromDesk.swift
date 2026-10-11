// MARK: - Away from desk
// Rotation's own input for Dwell, which counts awake, unlocked time: screens asleep, a locked session or a switched
// away user stop it. Occlusion doesn't (working in an opaque app is still time at the desk), so it isn't an input.
// The coordinator forwards these before Presence hears them, so a switch on locking counts Dwell only up to the lock.

public enum AwayFromDesk: Equatable {
    case screensAsleep(Bool)
    case sessionInactive(Bool)
    case locked(Bool)
}
