import App
import Application

// MARK: - Presence adapters

extension Composition {
    static func presence() -> PresenceService {
        Visibility()
    }
}
