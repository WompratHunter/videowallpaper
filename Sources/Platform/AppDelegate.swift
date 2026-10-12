import AppKit
import Application
import Core

// MARK: - App delegate
// The entry point: it composes the adapters, owns the shared tick's clock, observes system notifications and forwards
// each to the coordinator, where the contexts meet. No routing lives here. The time zone notification arrives on an
// arbitrary queue and is hopped to the main thread. Lock and unlock are Presence's, behind its lock signal port;
// screen, session and power notifications are Playback's ports.

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
}
