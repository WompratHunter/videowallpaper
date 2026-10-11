import Foundation

// MARK: - System Presence clock
// The Presence clock port's adapter: the wall clock and one main-queue timer for the coverage expiry.

@MainActor
public final class SystemPresenceClock: PresenceClockPort {
    private var pending: DispatchWorkItem?

    public init() {}

    public var now: Date { Date() }

    public func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        pending?.cancel()
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
