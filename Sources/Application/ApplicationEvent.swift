import SharedKernel

// MARK: - Application events
// What the Application layer's own commands report (Set Launch at login, Enable / Disable, Choose Wallpaper folder),
// as opposed to a context's events. Empty until the first command lands (tickets 09-12); each case gets its single
// log rendering in `logLine`, which the compiler keeps exhaustive.

public enum ApplicationEvent: Equatable {}

extension ApplicationEvent {
    /// Nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {}
    }
}
