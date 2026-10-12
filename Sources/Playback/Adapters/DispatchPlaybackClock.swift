import Foundation
import SharedKernel

// MARK: - Dispatch clock
// The Playback clock's adapter: system uptime, and delayed work on the main queue.

@MainActor
package final class DispatchPlaybackClock: PlaybackClock {
    package init() {}

    package var uptime: Uptime { ProcessInfo.processInfo.systemUptime }

    package func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> ScheduledWork {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return item
    }
}

extension DispatchWorkItem: ScheduledWork {}
