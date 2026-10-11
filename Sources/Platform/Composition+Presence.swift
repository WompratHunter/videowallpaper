import Core
import Foundation
import Presence

// MARK: - Presence adapters

extension Composition {
    static func presence() -> PresenceService {
        PresenceService(
            lockSignal: DistributedLockSignal(), windowList: SystemWindowList(), clock: SystemPresenceClock())
    }

    /// `--check-veil`: samples coverage every 5 s for 45 s and logs each sample, so Veiled can be checked by hand
    /// before anything in the app asks for it. Runs in its own process, never touching the running app.
    static func runVeilProbe() -> Never {
        let probe = presence()
        probe.onEvent = { event in
            guard let line = event.logLine else { return }
            Log.write(line.cause, line.message)
        }
        var remaining = 9
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let line = probe.probeVeil()
                Log.write(line.cause, line.message)
            }
            remaining -= 1
            if remaining == 0 { exit(0) }
        }
        RunLoop.main.run()
        exit(0)
    }
}
