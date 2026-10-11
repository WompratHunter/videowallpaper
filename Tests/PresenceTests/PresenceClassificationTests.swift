import Foundation
@testable import Presence
import SharedKernel
import Testing

// MARK: - Presence classification tests

struct PresenceClassificationTests {
    @Test(arguments: [
        (PresenceInputs(), SharedKernel.Presence.visible),
        (PresenceInputs(isEveryWindowOccluded: true), .unseen),
        (PresenceInputs(areScreensAsleep: true), .unseen),
        (PresenceInputs(isSessionInactive: true), .unseen),
        (PresenceInputs(isLocked: true), .unseen),
        (PresenceInputs(coveredFor: 30), .veiled),
        (PresenceInputs(coveredFor: 29.9), .visible),
        // Unseen wins: a locked screen behind a maximized window is still nobody watching.
        (PresenceInputs(isLocked: true, coveredFor: 60), .unseen)
    ])
    func classifies(_ inputs: PresenceInputs, as expected: SharedKernel.Presence) {
        #expect(classifyPresence(inputs) == expected)
    }

    @Test func unlockAloneDoesNotClearUnseenWhileTheScreensSleep() {
        var inputs = PresenceInputs()
        inputs.apply(.screensAsleep(true))
        inputs.apply(.locked(true))
        inputs.apply(.locked(false))
        #expect(classifyPresence(inputs) == .unseen)
        inputs.apply(.screensAsleep(false))
        #expect(classifyPresence(inputs) == .visible)
        inputs.apply(.sessionInactive(true))
        #expect(classifyPresence(inputs) == .unseen)
        inputs.apply(.sessionInactive(false))
        inputs.apply(.everyWindowOccluded(true))
        #expect(classifyPresence(inputs) == .unseen)
    }
}

// MARK: - Presence tracking tests

struct PresenceTrackerTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func onlyChangesAreReported() {
        var tracker = PresenceTracker()
        #expect(tracker.state == .visible)
        #expect(tracker.needsCoverageSample, "Visible can become Veiled")

        #expect(tracker.apply(.screensAsleep(true), at: start) == .unseen)
        #expect(tracker.apply(.locked(true), at: start) == nil)
        #expect(!tracker.needsCoverageSample, "nothing to sample while Unseen")
        #expect(tracker.apply(.screensAsleep(false), at: start) == nil)
        #expect(tracker.apply(.locked(false), at: start) == .visible)
    }

    @Test func veiledOnTheTickThatReachesThirtySecondsThenLapses() {
        var tracker = PresenceTracker()
        var veiledAt: Date?
        for offset in stride(from: 0.0, through: 30, by: 5) where veiledAt == nil {
            if tracker.sample(coverage: 0.97, at: start + offset) == .veiled { veiledAt = start + offset }
        }
        #expect(veiledAt == start + 30)

        // Once nobody samples, Veiled lapses instead of going stale.
        #expect(tracker.refresh(at: start + 30 + VeilTracker.maxSampleGap) == nil)
        #expect(tracker.refresh(at: start + 30 + VeilTracker.maxSampleGap + 1) == .visible)
    }

    @Test func unseenOverridesVeiledAndLeavingItReturnsToCoverage() {
        var covered = PresenceTracker()
        for offset in stride(from: 0.0, through: 30, by: 5) { _ = covered.sample(coverage: 1, at: start + offset) }
        #expect(covered.state == .veiled)
        #expect(covered.apply(.everyWindowOccluded(true), at: start + 31) == .unseen)
        #expect(covered.apply(.everyWindowOccluded(false), at: start + 32) == .veiled)
    }
}
