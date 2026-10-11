import SharedKernel

// MARK: - Presence events
// What Presence tells the rest of the app, in order, on the main actor, each with its single log rendering. The log
// still says "visibility", as it always has.

public enum PresenceEvent: Equatable {
    /// Presence moved to a new state.
    case changed(to: Presence, because: PresenceChangeReason)
    /// Window coverage was read: on each tick while a switch is due, or by the veil probe. Not logged.
    case coverageSampled(Double)
    /// The window list couldn't be read, so this sample counts the desktop as uncovered.
    case windowListUnavailable
}

/// What moved Presence.
public enum PresenceChangeReason: Equatable {
    /// A system input; `cause` names the system event behind it (`lock`, `occlusion`, `screens-sleep`, …).
    case input(PresenceInput, cause: String)
    /// A coverage sample (Veiled after 30 s at or above 95 %, or back when it drops).
    case coverage(Double)
    /// Nobody sampled coverage recently, so the last sample no longer proves the desktop is covered.
    case coverageLapsed
}

extension PresenceEvent {
    /// Nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {
        case .changed(let state, .input(let input, let cause)):
            return LogLine(cause: cause, message: "visibility=\(state.rawValue) \(input.logDescription)")
        case .changed(let state, .coverage(let coverage)):
            return LogLine(cause: "veil", message: "visibility=\(state.rawValue) coverage=\(percent(coverage))")
        case .changed(let state, .coverageLapsed):
            return LogLine(cause: "veil", message: "visibility=\(state.rawValue) no recent coverage sample")
        case .coverageSampled:
            return nil
        case .windowListUnavailable:
            return LogLine(cause: "veil", message: "window list unavailable; counting the desktop as uncovered")
        }
    }
}
