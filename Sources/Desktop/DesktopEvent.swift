import SharedKernel

// MARK: - Desktop events
// What Desktop tells the rest of the app, in order, on the main actor. Empty until ticket 05 moves the context here:
// each case it adds gets its single log rendering in `logLine`, which the compiler keeps exhaustive.

public enum DesktopEvent: Equatable {}

extension DesktopEvent {
    /// Nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {}
    }
}
