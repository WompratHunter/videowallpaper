import Foundation
import Presence

// MARK: - Fake Presence ports
// The real Presence service runs on these: a lock signal tests post to, a window list tests arrange, and a clock that
// reads the time it is given and runs its pending expiry only when asked.

@MainActor
package final class FakeLockSignal: LockSignalPort {
    package var onChange: (Bool) -> Void = { _ in }
    package private(set) var isStarted = false

    package init() {}

    package func start() {
        isStarted = true
    }

    package func lock() {
        onChange(true)
    }

    package func unlock() {
        onChange(false)
    }
}

@MainActor
package final class FakeWindowList: WindowListPort {
    package static let screen = ScreenRect(minX: 0, minY: 0, width: 1_000, height: 800)

    /// Nil stands for a window list that can't be read.
    package var listed: [ListedWindow]? = []
    package var displays = [FakeWindowList.screen]
    package private(set) var reads = 0

    package init() {}

    /// One normal opaque window over every display.
    package func coverEveryScreen() {
        listed = displays.map { ListedWindow(layer: 0, alpha: 1, bounds: $0) }
    }

    package func windows() -> [ListedWindow]? {
        reads += 1
        return listed
    }

    package func screens() -> [ScreenRect] { displays }
}

@MainActor
package final class FakePresenceClock: PresenceClockPort {
    private let readNow: () -> Date
    private var pending: (due: Date, work: @MainActor () -> Void)?

    /// `now` is read on every call, so the clock can follow another fake's time.
    package init(now: @escaping () -> Date) {
        readNow = now
    }

    package var now: Date { readNow() }

    package func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        pending = (now.addingTimeInterval(delay), work)
    }

    /// Runs the pending call if it has fallen due.
    package func runDue() {
        guard let pending, pending.due <= now else { return }
        self.pending = nil
        pending.work()
    }
}
