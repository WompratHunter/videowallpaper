import Presence
import Rotation
import SharedKernel

// MARK: - Presence routes
// What Presence hears (occlusion, screens asleep, session, lock) and where its changes go. Dwell hears of a lock,
// sleep or session change before Presence reports it, so a switch on locking counts Dwell only up to the lock; and a
// Presence change asks the Rotation to decide at once, since an Unseen or Veiled moment is a switch point.

extension Coordinator {
    func connectPresence() {
        presence.onEvent = { [weak self] event in self?.handle(event) }
        presence.observeLock { [weak self] isLocked in
            if isLocked { self?.screenLocked() } else { self?.screenUnlocked() }
        }
    }

    private func handle(_ event: PresenceEvent) {
        emit(.presence(event))
        guard case .changed = event else { return }
        evaluateRotation(cause: "visibility")
    }

    func notePresenceInput(_ input: PresenceInput, cause: String) {
        if let away = input.awayFromDesk { rotationAwayFromDesk(away) }
        presence.apply(input, cause: cause)
    }

    // MARK: - Presence commands

    var currentPresence: Presence { presence.state }

    func sampleVeil() -> Presence {
        presence.checkVeil()
    }

    // MARK: - System inputs

    private func screenLocked() {
        notePresenceInput(.locked(true), cause: "lock")
    }

    private func screenUnlocked() {
        notePresenceInput(.locked(false), cause: "unlock")
        playbackResetBackoff(on: .unlock)
        playbackVerify(cause: "unlock")
    }
}

extension PresenceInput {
    /// What the Rotation hears of this input: occlusion is still time at the desk, so it hears nothing of it.
    fileprivate var awayFromDesk: AwayFromDesk? {
        switch self {
        case .everyWindowOccluded: return nil
        case .screensAsleep(let isOn): return .screensAsleep(isOn)
        case .sessionInactive(let isOn): return .sessionInactive(isOn)
        case .locked(let isOn): return .locked(isOn)
        }
    }
}
