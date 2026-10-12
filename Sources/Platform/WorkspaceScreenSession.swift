import AppKit
import Playback

// MARK: - Screen and session notifications
// The screen/session port's adapter: NSWorkspace's screen sleep/wake, system wake and session notifications, and
// NSApplication's screen parameters change. All are posted on the main thread.

@MainActor
final class WorkspaceScreenSession: ScreenSessionPort {
    var onEvent: (ScreenSessionEvent) -> Void = { _ in }
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification, .screensDidSleep)
        observe(workspace, NSWorkspace.screensDidWakeNotification, .screensDidWake)
        observe(workspace, NSWorkspace.didWakeNotification, .systemDidWake)
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionDidBecomeActive)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionDidResignActive)
        let application = NotificationCenter.default
        observe(application, NSApplication.didChangeScreenParametersNotification, .screenParametersChanged)
    }

    deinit {
        observers.forEach { $0.center.removeObserver($0.token) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ event: ScreenSessionEvent) {
        let token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent(event) }
        }
        observers.append((center, token))
    }
}
