import AppKit

// MARK: - Rotation scheduler
// Gathers what a Rotation decision reads (the clock, eligible videos, Visibility, the `Mode` setting and Daylight)
// and hands the decision's switch to the wiring. Every decision and its state are in Core
// (`RotationState`); this only reads inputs, logs and applies.

final class RotationScheduler {
    /// Called on the main queue to switch the Live wallpaper to a video with a crossfade of the given seconds.
    var onSwitch: (URL, TimeInterval) -> Void = { _, _ in }
    var eligibleVideos: () -> [EligibleVideo] = { [] }
    var visibility: () -> VisibilityState = { .visible }
    /// Samples window coverage for Veiled; asked only while a switch point is near.
    var checkVeil: () -> VisibilityState = { .visible }
    var isPowerSaving: () -> Bool = { false }
    /// The raw `Mode` setting, read at every decision so a change applies without a restart.
    var modeSetting: () -> String? = { nil }
    /// Whether the system appearance switches automatically (read only), which makes `dynamic` the default Mode.
    var isAutoAppearance: () -> Bool = { false }
    /// Where Daylight is computed for, and where that came from.
    var location: () -> (coordinates: Coordinates, source: LocationSource)? = { nil }
    /// The time Daylight is computed for.
    var clock: () -> Date = { Date() }
    /// `dynamic` is in effect, so the location is wanted: called on every such decision.
    var onDynamicMode: () -> Void = {}

    private let directory: URL
    private var state: RotationState
    private var rng = SystemRandomNumberGenerator()
    private var isWaitingForUnseen = false
    private var isDeciding = false
    private var loggedMode: String?

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// `present`: the folder's videos at launch, which join the Rotation without counting as newly added.
    init(directory: URL, present: Set<String>, dwellScale: Double) {
        self.directory = directory
        state = RotationState(present: present, dwellScale: dwellScale)
        if dwellScale != 1 { Log.write("rotation", "debug Dwell scale=\(dwellScale)") }
    }

    /// The Current video: what a rebuild or a folder change should play.
    var video: URL? { state.current.map { directory.appendingPathComponent($0.name) } }

    /// Picks the first video, for the player's start to build. Call once at launch.
    func start() {
        refresh(cause: "launch")
    }

    /// On the shared tick and on a Visibility change: decides, and switches if the moment allows.
    func evaluate(cause: String) {
        guard let change = decide(cause: cause, sampleVeil: true), !change.isDeferred else { return }
        onSwitch(directory.appendingPathComponent(change.to.name), change.fade)
    }

    /// On a folder change or a rebuild: decides without switching, since the caller hands `video` to the player.
    @discardableResult
    func refresh(cause: String) -> RotationSwitch? {
        decide(cause: cause, sampleVeil: false)
    }

    /// Lock, screen sleep and session changes pause and resume Dwell.
    func apply(_ event: VisibilityEvent) {
        state.apply(event, at: now)
    }

    private func decide(cause: String, sampleVeil: Bool) -> RotationSwitch? {
        // Sampling coverage can itself report a Visibility change, which asks for a decision: this one covers it.
        guard !isDeciding else { return nil }
        isDeciding = true
        defer { isDeciding = false }
        let mode = currentMode()
        if mode == .dynamic { onDynamicMode() }
        let daylight = currentDaylight()
        var situation = RotationSituation(
            now: now, eligible: eligibleVideos(), visibility: visibility(), mode: mode, daylight: daylight.level,
            isPowerSaving: isPowerSaving())
        if sampleVeil && state.isSwitchPointNear(situation) { situation.visibility = checkVeil() }
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
            log(change, on: cause, situation: situation, dwell: dwell, daylightSource: daylight.source)
            return change
        }
    }

    private func log(
        _ change: RotationSwitch,
        on cause: String,
        situation: RotationSituation,
        dwell: TimeInterval,
        daylightSource: String
    ) {
        let deltaL = change.deltaL.map { String(format: "%.3f", $0) } ?? "n/a"
        let rank = brightnessRanks(situation.eligible)[change.to.name].map { String(format: "%.2f", $0) } ?? "n/a"
        Log.write("rotation", "switch reason=\(change.reason.rawValue) on=\(cause) "
            + "from=\(change.from?.name ?? "none") to=\(change.to.name) ΔL=\(deltaL) fade=\(Int(change.fade))s "
            + "visibility=\(situation.visibility.rawValue) mode=\(situation.mode.rawValue) "
            + String(format: "daylight=%.2f rank=%@ location=%@ ", situation.daylight, rank, daylightSource)
            + "dwell=\(Int(dwell / 60))m"
            + (change.isDeferred ? " (Low Power Mode: plays when it ends)" : ""))
    }
}

// MARK: - Mode and Daylight

extension RotationScheduler {
    /// The `Mode` setting, defaulting by the auto-appearance flag. Logged when it changes.
    private func currentMode() -> RotationMode {
        let setting = modeSetting()
        let isAuto = isAutoAppearance()
        let mode = rotationMode(setting: setting, isAutoAppearance: isAuto)
        let description = "mode=\(mode.rawValue) setting=\(setting ?? "none") auto-appearance=\(isAuto ? "yes" : "no")"
        if description != loggedMode {
            Log.write("rotation", description)
            loggedMode = description
        }
        return mode
    }

    /// Daylight from the sun where the Mac is. With no place at all (a time zone like UTC and no fix), the
    /// appearance stands in: Dark as night, Light as day.
    private func currentDaylight() -> (level: Double, source: String) {
        if let place = location() {
            return (daylightLevel(at: clock(), at: place.coordinates), place.source.rawValue)
        }
        return (Self.currentAppearance() == .dark ? 0 : 1, "appearance")
    }

    private static func currentAppearance() -> Appearance {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

// MARK: - Debug Dwell

extension RotationScheduler {
    /// A manual test's shortened Dwell: `VIDEOWALLPAPER_DWELL_SCALE` (e.g. 0.01 makes 20 min 12 s), honoured only by
    /// a `make debug` build, so the installed app can't be affected.
    static var debugDwellScale: Double {
        #if DEBUG
        let scale = ProcessInfo.processInfo.environment["VIDEOWALLPAPER_DWELL_SCALE"].flatMap(Double.init)
        return scale.map { max($0, 0.001) } ?? 1
        #else
        return 1
        #endif
    }
}
