import SharedKernel

// MARK: - Playback events
// What Playback tells the rest of the app, in order, on the main actor. Empty until ticket 07 moves the context here:
// each case it adds gets its single log rendering in `logLine`, which the compiler keeps exhaustive.

public enum PlaybackEvent: Equatable {}

extension PlaybackEvent {
    /// Nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {}
    }
}
