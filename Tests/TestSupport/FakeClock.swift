import Application
import Foundation
import SharedKernel

// MARK: - Fake clock
// A clock tests step by hand: `advance(by:)` moves uptime and the wall clock together and runs every tick that falls
// due on the way, in order, as the 5 s timer would.

package final class FakeClock: ClockPort {
    package private(set) var uptime: Uptime = 1_000
    package private(set) var now = Date(timeIntervalSince1970: 1_791_032_645)
    private var tick: (() -> Void)?
    private var interval: TimeInterval = 0
    private var nextTick: Uptime = .infinity

    package init() {}

    package func startTicking(every interval: TimeInterval, tolerance: TimeInterval, _ tick: @escaping () -> Void) {
        self.tick = tick
        self.interval = interval
        nextTick = uptime + interval
    }

    package func advance(by seconds: TimeInterval) {
        let end = uptime + seconds
        while nextTick <= end {
            move(to: nextTick)
            nextTick += interval
            tick?()
        }
        move(to: end)
    }

    private func move(to time: Uptime) {
        now = now.addingTimeInterval(time - uptime)
        uptime = time
    }
}
