import SharedKernel

// MARK: - Application events
// What the Application layer's own commands report (Set Launch at login, Enable / Disable, Choose Wallpaper folder),
// as opposed to a context's events. Each case gets its single log rendering in `logLine`, which the compiler keeps
// exhaustive.

public enum ApplicationEvent: Equatable {
    /// Set Launch at login succeeded: the app will (or won't) start at the next login.
    case launchAtLoginSet(isOn: Bool)
    case launchAtLoginFailed(LaunchAtLoginFailure)
}

extension ApplicationEvent {
    /// Nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {
        case .launchAtLoginSet(let isOn):
            return LogLine(cause: "launch-at-login", message: isOn ? "on" : "off")
        case .launchAtLoginFailed(.couldNotTurnOn(let reason)):
            return LogLine(cause: "launch-at-login", message: "could not turn on: \(reason)")
        case .launchAtLoginFailed(.couldNotTurnOff(let reason)):
            return LogLine(cause: "launch-at-login", message: "could not turn off: \(reason)")
        }
    }
}
