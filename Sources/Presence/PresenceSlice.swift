import SharedKernel

// MARK: - Presence slice
// Presence's part of the app snapshot: whether a switch would be seen right now.

public struct PresenceSlice: Equatable {
    public var current: Presence

    public init(current: Presence = .visible) {
        self.current = current
    }
}
