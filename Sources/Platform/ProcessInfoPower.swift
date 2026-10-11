import Application
import Foundation

// MARK: - Power state
// The power port's adapter: Low Power Mode as the system reports it. Its change notification is observed by the
// app delegate.

final class ProcessInfoPower: PowerPort {
    var isLowPowerModeEnabled: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
}
