import Foundation
import SharedKernel

// MARK: - Presence service
// Whether the Live wallpaper can be seen: Unseen, Veiled or Visible (see CONTEXT.md). Unseen follows the inputs the
// coordinator forwards, with no polling. Veiled needs the window list, which is read only when a caller asks
// (`checkVeil`, on each tick while a switch is due), so an idle desktop never pays for it.

@MainActor
public final class PresenceService {
    /// Every event, in order; the coordinator sets it.
    public var onEvent: (PresenceEvent) -> Void = { _ in }

    public var state: Presence { tracker.state }
    public var slice: PresenceSlice { PresenceSlice(current: state) }

    private let lockSignal: LockSignalPort
    private let windowList: WindowListPort
    private let clock: PresenceClockPort
    private var tracker = PresenceTracker()

    public init(lockSignal: LockSignalPort, windowList: WindowListPort, clock: PresenceClockPort) {
        self.lockSignal = lockSignal
        self.windowList = windowList
        self.clock = clock
    }

    /// Starts listening for lock and unlock. The coordinator hears them first, so Dwell can stop before Presence
    /// changes, and then forwards them back through `apply`.
    public func observeLock(_ onChange: @escaping (_ isLocked: Bool) -> Void) {
        lockSignal.onChange = onChange
        lockSignal.start()
    }

    public func apply(_ input: PresenceInput, cause: String) {
        report(tracker.apply(input, at: clock.now), because: .input(input, cause: cause))
    }

    /// Samples window coverage and returns the state that follows. Call it on every tick while a switch is due:
    /// Veiled needs 30 s of continuous samples.
    @discardableResult
    public func checkVeil() -> Presence {
        sampleCoverage()
        return state
    }

    /// `--check-veil`: samples coverage now and renders the probe's line for it.
    public func probeVeil() -> LogLine {
        let coverage = sampleCoverage().map(percent) ?? "n/a"
        return LogLine(cause: "veil-probe", message: "coverage=\(coverage) state=\(state.rawValue)")
    }

    /// Returns the coverage sampled, or nil when Unseen made the window list not worth reading.
    @discardableResult
    private func sampleCoverage() -> Double? {
        guard tracker.needsCoverageSample else { return nil }
        let coverage = currentCoverage()
        onEvent(.coverageSampled(coverage))
        report(tracker.sample(coverage: coverage, at: clock.now), because: .coverage(coverage))
        scheduleVeilExpiry()
        return coverage
    }

    /// The least-covered screen's coverage by on-screen normal-layer windows.
    private func currentCoverage() -> Double {
        guard let windows = windowList.windows() else {
            onEvent(.windowListUnavailable)
            return 0
        }
        return leastCoverage(of: windows, screens: windowList.screens())
    }

    /// Once callers stop asking, the last sample stops proving coverage; re-check just after it lapses so a stale
    /// Veiled is reported as the change it is.
    private func scheduleVeilExpiry() {
        clock.schedule(after: VeilTracker.maxSampleGap + 1) { [weak self] in
            guard let self else { return }
            self.report(self.tracker.refresh(at: self.clock.now), because: .coverageLapsed)
        }
    }

    private func report(_ change: Presence?, because reason: PresenceChangeReason) {
        guard let change else { return }
        onEvent(.changed(to: change, because: reason))
    }
}
