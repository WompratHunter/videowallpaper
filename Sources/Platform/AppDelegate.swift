import AppKit
import Application
import Core

// MARK: - App delegate
// The entry point: it composes the adapters, owns the shared tick's clock, observes system notifications and forwards
// each to the coordinator, where the contexts meet. No routing lives here. Workspace and distributed notifications
// arrive on the main thread; the two that don't are hopped there.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let clock = SystemClock()
    private var coordinator: Coordinator?

    func applicationDidFinishLaunching(_ n: Notification) {
        Log.write("launch", "pid=\(ProcessInfo.processInfo.processIdentifier) screens=\(NSScreen.screens.count)")
        let coordinator = Composition.coordinator(clock: clock)
        StderrLogSink.attach(to: coordinator)
        self.coordinator = coordinator
        coordinator.launch()
        observeSystemEvents()
    }
}

// MARK: - Notifications

extension AppDelegate {
    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self, selector: #selector(screensSleep),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(screensWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(systemWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(sessionActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(sessionInactive),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        // Unlock has no public NSWorkspace notification; this distributed one is what the system posts.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        // Lock is expected to occlude every window too; this keeps Unseen correct if it doesn't.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerStateChanged),
            name: .NSProcessInfoPowerStateDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(timeZoneChanged),
            name: .NSSystemTimeZoneDidChange, object: nil)
    }

    /// Posted on an arbitrary queue.
    @objc private func timeZoneChanged() {
        DispatchQueue.main.async { [weak self] in
            NSTimeZone.resetSystemTimeZone()
            self?.coordinator?.timeZoneChanged()
        }
    }

    @objc private func screensSleep() {
        Log.write("screens-sleep", "pausing shared player")
        coordinator?.screensDidSleep()
    }

    @objc private func screensWake() { coordinator?.screensDidWake() }

    /// Posted on an arbitrary queue; the player is main-thread only.
    @objc private func powerStateChanged() {
        DispatchQueue.main.async { [weak self] in
            Log.write("power", "low-power=\(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")")
            self?.coordinator?.powerStateChanged()
        }
    }

    @objc private func systemWake() { coordinator?.systemDidWake() }

    @objc private func sessionActive() { coordinator?.sessionDidBecomeActive() }

    @objc private func sessionInactive() { coordinator?.sessionDidResignActive() }

    @objc private func screenLocked() { coordinator?.screenLocked() }

    @objc private func screenUnlocked() { coordinator?.screenUnlocked() }

    @objc private func screensChanged() { coordinator?.screenParametersChanged() }
}
