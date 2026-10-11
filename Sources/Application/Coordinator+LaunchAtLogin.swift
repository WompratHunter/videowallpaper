// MARK: - Set Launch at login
// The Application layer's own command (Launch at login belongs to no context): turns starting at login on or off
// through the launch-at-login port, reports it as an event and shows the port's state in the snapshot's Preferences.

/// Why Set Launch at login could not be done; `reason` is the system's description of the error.
public enum LaunchAtLoginFailure: Error, Equatable {
    case couldNotTurnOn(reason: String)
    case couldNotTurnOff(reason: String)
}

extension Coordinator {
    /// Starts the app at login, or stops it doing so, from the next login on; the running app is unaffected.
    @discardableResult
    public func setLaunchAtLogin(_ isOn: Bool) -> Result<Void, LaunchAtLoginFailure> {
        do {
            try launchAtLogin.setEnabled(isOn)
        } catch {
            let reason = error.localizedDescription
            let failure: LaunchAtLoginFailure = isOn
                ? .couldNotTurnOn(reason: reason) : .couldNotTurnOff(reason: reason)
            emit(.application(.launchAtLoginFailed(failure)))
            return .failure(failure)
        }
        emit(.application(.launchAtLoginSet(isOn: isOn)))
        return .success(())
    }

    /// Preferences as stored, with Launch at login as the port reports it.
    var preferences: Preferences {
        var preferences = settings.load()
        preferences.launchesAtLogin = launchAtLogin.isEnabled
        return preferences
    }
}
