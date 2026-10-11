import Application
import Core
import Presence
import SharedKernel

// MARK: - Fake Presence
// Stands in for the Presence service until ticket 03 replaces it with fakes of the lock/unlock and window-list ports.
// Tests set the state; a change is reported as the real service does.

package final class FakePresence: PresenceService {
    package var onChange: (Presence) -> Void = { _ in }
    package var state: Presence = .visible {
        didSet { if state != oldValue { onChange(state) } }
    }

    package init() {}

    package var slice: PresenceSlice { PresenceSlice() }

    package func apply(_ event: VisibilityEvent, cause: String) {}

    package func checkVeil() -> Presence { state }
}
