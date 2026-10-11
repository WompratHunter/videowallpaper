import Foundation
import SharedKernel

// MARK: - Presence classification
// Whether anyone can see the Live wallpaper (see CONTEXT.md): its Presence. Unseen comes from notifications; Veiled
// from window-list bounds sampled only when a caller asks, so it needs no Screen Recording permission and costs nothing
// while no switch is due.

/// A notification-driven input change; the window-list coverage arrives separately, through `VeilTracker`.
public enum PresenceInput: Equatable, Sendable {
    /// No wallpaper window is visible. Translucent windows (e.g. Ghostty) don't clear a window's visible flag, so a
    /// translucent cover never makes this true.
    case everyWindowOccluded(Bool)
    case screensAsleep(Bool)
    case sessionInactive(Bool)
    case locked(Bool)

    /// How the log names this input, as it always has.
    var logDescription: String {
        switch self {
        case .everyWindowOccluded(let isOn): return "everyWindowOccluded(\(isOn))"
        case .screensAsleep(let isOn): return "screensAsleep(\(isOn))"
        case .sessionInactive(let isOn): return "sessionInactive(\(isOn))"
        case .locked(let isOn): return "locked(\(isOn))"
        }
    }
}

struct PresenceInputs: Equatable {
    var isEveryWindowOccluded = false
    var areScreensAsleep = false
    var isSessionInactive = false
    var isLocked = false
    /// How long normal windows have covered every screen continuously, or nil if they don't (see `VeilTracker`).
    var coveredFor: TimeInterval?
}

extension PresenceInputs {
    mutating func apply(_ input: PresenceInput) {
        switch input {
        case .everyWindowOccluded(let isOn): isEveryWindowOccluded = isOn
        case .screensAsleep(let isOn): areScreensAsleep = isOn
        case .sessionInactive(let isOn): isSessionInactive = isOn
        case .locked(let isOn): isLocked = isOn
        }
    }
}

func classifyPresence(_ inputs: PresenceInputs) -> Presence {
    if inputs.isEveryWindowOccluded || inputs.areScreensAsleep || inputs.isSessionInactive || inputs.isLocked {
        return .unseen
    }
    if let coveredFor = inputs.coveredFor, coveredFor >= VeilTracker.requiredDuration { return .veiled }
    return .visible
}

// MARK: - Presence tracking

/// The current state and what moves it: inputs, coverage samples and the expiry of the last sample. Each step returns
/// the new state only when it changed, so the service reports exactly the changes.
struct PresenceTracker {
    private(set) var state: Presence = .visible
    private var inputs = PresenceInputs()
    private var veil = VeilTracker()

    /// Veiled can't override Unseen, so the window list isn't worth reading then.
    var needsCoverageSample: Bool { classifyPresence(inputs) != .unseen }

    mutating func apply(_ input: PresenceInput, at now: Date) -> Presence? {
        inputs.apply(input)
        return refresh(at: now)
    }

    mutating func sample(coverage: Double, at now: Date) -> Presence? {
        veil.sample(coverage: coverage, at: now)
        return refresh(at: now)
    }

    /// Re-reads the coverage clock: once the last sample is older than `VeilTracker.maxSampleGap`, Veiled lapses.
    mutating func refresh(at now: Date) -> Presence? {
        inputs.coveredFor = veil.coveredFor(at: now)
        let next = classifyPresence(inputs)
        guard next != state else { return nil }
        state = next
        return next
    }
}
