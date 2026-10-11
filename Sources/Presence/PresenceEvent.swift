import SharedKernel

// MARK: - Presence events
// What Presence tells the rest of the app, in order, on the main actor. Empty until ticket 03 moves the context here:
// each case it adds gets its single log rendering in `logLine`, which the compiler keeps exhaustive.

public enum PresenceEvent: Equatable {}

extension PresenceEvent {
    /// Nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {}
    }
}
