import SharedKernel

// MARK: - Library events
// What the Library tells the rest of the app, in order, on the main actor. Each case has its single log rendering
// here; Platform's log sink writes it, so the log and a future UI read the same facts.

public enum LibraryEvent: Equatable {
    /// The eligible set changed after a settle check or an Analysis. Rotation hears it before Playback rebuilds.
    case eligibleSetChanged(eligible: [EligibleVideo], cause: EligibilityCause)
}

/// What changed the eligible set; it is also the log line's cause.
public enum EligibilityCause: String, Equatable {
    case analysis
    case folderChange = "folder-change"
}

extension LibraryEvent {
    /// Nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {
        case let .eligibleSetChanged(eligible, cause):
            return LogLine(cause: cause.rawValue, message: "eligible videos=\(eligible.count)")
        }
    }
}
