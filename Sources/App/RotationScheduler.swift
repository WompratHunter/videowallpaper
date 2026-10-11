import Application
import Core
import Foundation
import Rotation
import SharedKernel

// MARK: - Rotation scheduler
// Reads what a Rotation decision needs (the inputs the coordinator connects: time, eligible videos, Presence, the
// `Mode` setting and Daylight), logs, and returns the switch for the coordinator to apply. Every decision and its
// state are in Core (`RotationState`).

package final class RotationScheduler {
    package var onEvent: (RotationEvent) -> Void = { _ in }
    /// Whether the system appearance switches automatically (read only), which makes `dynamic` the default Mode. The
    /// global flag is undocumented: absent reads as off, so the default Mode falls back to `all`.
    package var isAutoAppearance: () -> Bool = {
        UserDefaults.standard.bool(forKey: "AppleInterfaceStyleSwitchesAutomatically")
    }

    private let directory: URL
    private let dwellScale: Double
    private var inputs = RotationInputs()
    private var state: RotationState
    private var rng = SystemRandomNumberGenerator()
    private var isWaitingForUnseen = false
    private var isDeciding = false
    private var loggedMode: String?

    package init(directory: URL, dwellScale: Double) {
        self.directory = directory
        self.dwellScale = dwellScale
        state = RotationState(present: [], dwellScale: dwellScale)
        if dwellScale != 1 { Log.write("rotation", "debug Dwell scale=\(dwellScale)") }
    }

    package var video: URL? { state.current.map { directory.appendingPathComponent($0.name) } }

    package var slice: RotationSlice { RotationSlice(current: state.current?.id) }

    package func connect(_ inputs: RotationInputs) {
        self.inputs = inputs
    }

    package func start(present: Set<String>) {
        state = RotationState(present: present, dwellScale: dwellScale)
        _ = refresh(cause: "launch")
    }

    package func evaluate(cause: String) -> (video: URL, fade: TimeInterval)? {
        guard let change = decide(cause: cause, sampleVeil: true), !change.isDeferred else { return nil }
        return (directory.appendingPathComponent(change.to.name), change.fade)
    }

    package func refresh(cause: String) -> RotationSwitch? {
        decide(cause: cause, sampleVeil: false)
    }

    package func apply(_ event: AwayFromDesk) {
        state.apply(event, at: inputs.uptime())
    }

    private func decide(cause: String, sampleVeil: Bool) -> RotationSwitch? {
        // Sampling coverage can itself report a Presence change, which asks for a decision: this one covers it.
        guard !isDeciding else { return nil }
        isDeciding = true
        defer { isDeciding = false }
        var situation = RotationSituation(
            now: inputs.uptime(), eligible: inputs.eligibleVideos(), visibility: inputs.presence(),
            mode: currentMode(), daylight: 0, isPowerSaving: inputs.isPowerSaving())
        var daylightSource: String?
        if situation.followsDaylight {
            let daylight = inputs.daylight()
            situation.daylight = daylight.level
            daylightSource = daylight.source
        }
        if sampleVeil && state.isSwitchPointNear(situation) { situation.visibility = inputs.checkVeil() }
        let dwell = state.dwell.elapsed
        switch state.decide(situation, using: &rng) {
        case .stay:
            return nil
        case .waitingForUnseen:
            if !isWaitingForUnseen {
                Log.write("rotation", "switch due but no allowed video within ΔL \(RotationRules.brightnessBand): "
                    + "waiting for Unseen (visibility=\(situation.visibility.rawValue))")
            }
            isWaitingForUnseen = true
            return nil
        case .switchTo(let change):
            isWaitingForUnseen = false
            log(change, on: cause, situation: situation, dwell: dwell, daylightSource: daylightSource)
            onEvent(.switchDecided(
                from: change.from?.id, to: change.to.id, reason: change.reason, fade: change.fade,
                isDeferred: change.isDeferred))
            return change
        }
    }

    private func log(
        _ change: RotationSwitch,
        on cause: String,
        situation: RotationSituation,
        dwell: TimeInterval,
        daylightSource: String?
    ) {
        let deltaL = change.deltaL.map { String(format: "%.3f", $0) } ?? "n/a"
        // Daylight is the Target brightness; the new video's rank shows how close the pick landed.
        let daylight = daylightSource.map { source in
            let rank = situation.ranks[change.to.name] ?? .nan
            return String(format: "daylight=%.2f target=%.2f to-rank=%.2f daylight-source=%@ ",
                          situation.daylight, situation.daylight, rank, source)
        } ?? ""
        Log.write("rotation", "switch reason=\(change.reason.rawValue) on=\(cause) "
            + "from=\(change.from?.name ?? "none") to=\(change.to.name) ΔL=\(deltaL) fade=\(Int(change.fade))s "
            + "visibility=\(situation.visibility.rawValue) mode=\(situation.mode.rawValue) " + daylight
            + "dwell=\(Int(dwell / 60))m"
            + (change.isDeferred ? " (Low Power Mode: plays when it ends)" : ""))
    }
}

extension RotationScheduler: RotationService {}

// MARK: - Mode

extension RotationScheduler {
    /// The `Mode` setting, defaulting by the auto-appearance flag. Logged when it changes.
    private func currentMode() -> RotationMode {
        let setting = inputs.modeSetting()
        let isAuto = isAutoAppearance()
        let mode = rotationMode(setting: setting, isAutoAppearance: isAuto)
        let description = "mode=\(mode.rawValue) setting=\(setting ?? "none") auto-appearance=\(isAuto ? "yes" : "no")"
        if description != loggedMode {
            Log.write("rotation", description)
            loggedMode = description
        }
        return mode
    }
}

// MARK: - Debug Dwell

extension RotationScheduler {
    /// A manual test's shortened Dwell: `VIDEOWALLPAPER_DWELL_SCALE` (e.g. 0.01 makes 20 min 12 s), honoured only by
    /// a `make debug` build, so the installed app can't be affected.
    package static var debugDwellScale: Double {
        #if DEBUG
        let scale = ProcessInfo.processInfo.environment["VIDEOWALLPAPER_DWELL_SCALE"].flatMap(Double.init)
        return scale.map { max($0, 0.001) } ?? 1
        #else
        return 1
        #endif
    }
}
