import Foundation
import Playback

// MARK: - Power state
// The power port's adapter: Low Power Mode as the system reports it, and its change notification.

@MainActor
final class ProcessInfoPower: PowerPort {
    var onChange: () -> Void = {}
    private var observer: NSObjectProtocol?

    init() {
        // Posted on an arbitrary queue; Playback is main-thread only.
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.onChange() }
        }
    }

    deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }

    var isLowPowerModeEnabled: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
}
