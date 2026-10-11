import Foundation
import SharedKernel

// MARK: - Clock port
// Time and the shared tick, so tests can step time. Today's adapter is Platform's `SystemClock` (system uptime, the
// wall clock, a 5 s repeating timer with 2 s tolerance); tests use `FakeClock`.

package protocol ClockPort: AnyObject {
    /// Seconds since boot: Dwell, Recovery and fades are measured in it.
    var uptime: Uptime { get }
    /// Wall-clock time: only for the sun and the log.
    var now: Date { get }
    /// Calls `tick` every `interval` seconds, on the main actor, for the app's lifetime. Called once, at launch.
    func startTicking(every interval: TimeInterval, tolerance: TimeInterval, _ tick: @escaping () -> Void)
}
