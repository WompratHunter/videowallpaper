import Application
import Rotation
import SharedKernel
import TestSupport
import Testing

// MARK: - Set Launch at login
// The command on a fake launch-at-login port: on, off and the state the snapshot reports, each with its event and log line.

@MainActor
struct LaunchAtLoginTests {
    @Test func theSnapshotReportsLaunchAtLoginFromThePort() {
        let app = AppHarness(library: FakeLibrary(eligible: []))
        app.launchAtLogin.isEnabled = false
        app.coordinator.launch()

        #expect(app.coordinator.snapshot.preferences.launchesAtLogin == false)
        // Only the Rotation's Mode in effect, read at launch's decision.
        #expect(app.eventsOutsideLibrary == [
            .rotation(.modeInEffect(mode: .all, setting: "all", isAutoAppearance: false))
        ])
    }

    @Test func turningItOffStopsTheNextLoginStart() throws {
        let app = AppHarness(library: FakeLibrary(eligible: []))
        app.coordinator.launch()
        let launched = app.events.count
        #expect(app.coordinator.snapshot.preferences.launchesAtLogin)

        try app.coordinator.setLaunchAtLogin(false).get()

        #expect(app.launchAtLogin.isEnabled == false)
        #expect(Array(app.events.dropFirst(launched)) == [.application(.launchAtLoginSet(isOn: false))])
        #expect(app.events.last?.logLine == LogLine(cause: "launch-at-login", message: "off"))
        #expect(app.coordinator.snapshot.preferences.launchesAtLogin == false)
        #expect(app.snapshots.last == app.coordinator.snapshot)
        // Launch at login isn't kept in the settings store.
        #expect(app.settings.stored == Preferences(modeSetting: "all"))
    }

    @Test func turningItOnStartsTheAppAtTheNextLogin() throws {
        let app = AppHarness(library: FakeLibrary(eligible: []))
        app.launchAtLogin.isEnabled = false
        app.coordinator.launch()
        let launched = app.events.count

        try app.coordinator.setLaunchAtLogin(true).get()

        #expect(app.launchAtLogin.isEnabled)
        #expect(Array(app.events.dropFirst(launched)) == [.application(.launchAtLoginSet(isOn: true))])
        #expect(app.events.last?.logLine == LogLine(cause: "launch-at-login", message: "on"))
        #expect(app.coordinator.snapshot.preferences.launchesAtLogin)
    }

    @Test(arguments: [true, false])
    func aFailedChangeReportsWhyAndLeavesTheStateAlone(isOn: Bool) {
        let app = AppHarness(library: FakeLibrary(eligible: []))
        app.launchAtLogin.isEnabled = !isOn
        app.launchAtLogin.failure = FakeLaunchAtLogin.Failure("disk full")
        app.coordinator.launch()
        let launched = app.events.count

        let failure: LaunchAtLoginFailure = isOn
            ? .couldNotTurnOn(reason: "disk full") : .couldNotTurnOff(reason: "disk full")
        #expect(throws: failure) { try app.coordinator.setLaunchAtLogin(isOn).get() }

        #expect(Array(app.events.dropFirst(launched)) == [.application(.launchAtLoginFailed(failure))])
        #expect(app.events.last?.logLine == LogLine(
            cause: "launch-at-login", message: "could not turn \(isOn ? "on" : "off"): disk full"))
        #expect(app.coordinator.snapshot.preferences.launchesAtLogin == !isOn)
    }
}
