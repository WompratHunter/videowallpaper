import Core
import Presence
import SharedKernel

// MARK: - Presence service
// Presence as the coordinator sees it, with today's `Visibility` (Sources/App) as its adapter. A seam for the move
// only: ticket 03 replaces it with the Presence context's own service, built on lock/unlock and window-list ports.

package protocol PresenceService: AnyObject {
    /// Called on the main queue whenever `state` changes.
    var onChange: (Presence) -> Void { get set }
    var state: Presence { get }
    var slice: PresenceSlice { get }

    func apply(_ event: VisibilityEvent, cause: String)
    /// Samples window coverage and returns the state that follows. Veiled needs 30 s of continuous samples.
    func checkVeil() -> Presence
}
