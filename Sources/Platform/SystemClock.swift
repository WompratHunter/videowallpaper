import Application
import Foundation
import SharedKernel

// MARK: - System clock
// The clock port's adapter: system uptime, the wall clock, and the shared tick as a repeating main run loop timer.
// It owns the timer for the app's lifetime.

final class SystemClock: ClockPort {
    private var timer: Timer?

    var uptime: Uptime { ProcessInfo.processInfo.systemUptime }

    var now: Date { Date() }

    func startTicking(every interval: TimeInterval, tolerance: TimeInterval, _ tick: @escaping () -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in tick() }
        timer.tolerance = tolerance
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }
}
