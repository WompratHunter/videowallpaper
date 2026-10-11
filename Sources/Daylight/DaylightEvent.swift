import SharedKernel

// MARK: - Daylight events
// What Daylight tells the rest of the app, in order, on the main actor. Empty until ticket 04 moves the context here:
// each case it adds gets its single log rendering in `logLine`, which the compiler keeps exhaustive.

public enum DaylightEvent: Equatable {}

extension DaylightEvent {
    /// Nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {}
    }
}
