// MARK: - Launch-at-login port
// Whether the app starts at login. It is the state's only store: Preferences' `launchesAtLogin` is read from here, not
// from the settings store. Today's adapter is Platform's `LaunchAgentLogin` (the user's LaunchAgent plist); the App
// Store phase swaps in `SMAppService`; tests use `FakeLaunchAtLogin`.

package protocol LaunchAtLoginPort: AnyObject {
    /// Whether the app will start at the next login.
    var isEnabled: Bool { get }
    /// Takes effect at the next login; never starts or stops the running app.
    func setEnabled(_ isEnabled: Bool) throws
}
