import Foundation
import SharedKernel

// MARK: - Rotation service
// The Rotation as the coordinator sees it: reads what a decision needs (the inputs the coordinator connects: time,
// eligible videos, Presence, Low Power Mode, the `Mode` setting and Daylight), decides, publishes events and its
// snapshot slice, and returns the switch for the coordinator to apply. Every decision and its state are in
// `RotationState`; the only OS signal it reads, the auto-appearance flag, comes through its port.

@MainActor
public final class RotationService {
    /// The Rotation's events, in order, on the main actor.
    public var onEvent: (RotationEvent) -> Void = { _ in }

    private let directory: URL
    private let dwellScale: Double
    private let appearance: AutoAppearancePort
    private var inputs = RotationInputs()
    private var state: RotationState
    private var rng: any RandomNumberGenerator
    private var isWaitingForUnseen = false
    private var isDeciding = false
    private var lastModeLine: LogLine?
    private var lastPresence: Presence?
    private var lastSwitch: SwitchReason?

    /// `directory`: the Wallpaper folder, where the Current video's file is. `dwellScale` shortens every minimum Dwell
    /// for a manual test of a debug build; 1 otherwise. `rng` makes the picks; a test passes a seeded one.
    public init(
        directory: URL,
        dwellScale: Double = 1,
        appearance: AutoAppearancePort,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.directory = directory
        self.dwellScale = dwellScale
        self.appearance = appearance
        self.rng = rng
        state = RotationState(present: [], dwellScale: dwellScale)
    }

    /// The Current video: what a rebuild or a folder change should play.
    public var video: URL? { state.current.map { directory.appendingPathComponent($0.name) } }

    public var slice: RotationSlice {
        RotationSlice(
            current: state.current?.id,
            statuses: state.statuses,
            dwell: state.dwell.elapsed,
            nextMinimumDwell: lastPresence.map(state.minimumDwell(for:)),
            lastSwitch: lastSwitch)
    }

    /// Set `onEvent` first: a debug build's Dwell scale is announced here.
    public func connect(_ inputs: RotationInputs) {
        self.inputs = inputs
        if dwellScale != 1 { onEvent(.debugDwellScale(dwellScale)) }
    }

    /// Picks the first video, for the player's start to build. Once, at launch: `present` (the folder's videos then)
    /// join the Rotation as their Analysis finishes, without counting as newly added.
    public func start(present: Set<String>) {
        state = RotationState(present: present, dwellScale: dwellScale)
        _ = refresh(cause: "launch")
    }

    /// On the tick and on a Presence change: decides, and returns the video to switch to if the moment allows.
    public func evaluate(cause: String) -> (video: URL, fade: TimeInterval)? {
        guard let change = decide(cause: cause, sampleVeil: true), !change.isDeferred else { return nil }
        return (directory.appendingPathComponent(change.to.name), change.fade)
    }

    /// On a folder change or a rebuild: decides without switching, since the caller hands `video` to the player.
    /// Returns the fade of the switch it decided, if any.
    @discardableResult
    public func refresh(cause: String) -> TimeInterval? {
        decide(cause: cause, sampleVeil: false)?.fade
    }

    /// Lock, screen sleep and session changes pause and resume Dwell.
    public func apply(_ event: AwayFromDesk) {
        state.apply(event, at: inputs.uptime())
    }

    private func decide(cause: String, sampleVeil: Bool) -> RotationSwitch? {
        // Sampling coverage can itself report a Presence change, which asks for a decision: this one covers it.
        guard !isDeciding else { return nil }
        isDeciding = true
        defer { isDeciding = false }
        var situation = RotationSituation(
            now: inputs.uptime(), eligible: inputs.eligibleVideos(), presence: inputs.presence(),
            mode: currentMode(), daylight: 0, isLowPowerMode: inputs.isLowPowerMode())
        var daylightSource: String?
        if situation.followsDaylight {
            let daylight = inputs.daylight()
            situation.daylight = daylight.level
            daylightSource = daylight.source
        }
        if sampleVeil && state.isSwitchPointNear(situation) { situation.presence = inputs.checkVeil() }
        lastPresence = situation.presence
        let dwell = state.dwell.elapsed
        switch state.decide(situation, using: &rng) {
        case .stay:
            return nil
        case .waitingForUnseen:
            if !isWaitingForUnseen { onEvent(.waitingForUnseen(presence: situation.presence)) }
            isWaitingForUnseen = true
            return nil
        case .switchTo(let change):
            isWaitingForUnseen = false
            lastSwitch = change.reason
            onEvent(.switchDecided(
                decision(change, on: cause, situation: situation, dwell: dwell, daylightSource: daylightSource)))
            return change
        }
    }

    private func decision(
        _ change: RotationSwitch,
        on cause: String,
        situation: RotationSituation,
        dwell: TimeInterval,
        daylightSource: String?
    ) -> SwitchDecision {
        let target = daylightSource.map { source in
            TargetBrightness(
                daylight: situation.daylight, pickRank: situation.ranks[change.to.name] ?? .nan,
                daylightSource: source)
        }
        return SwitchDecision(
            from: change.from?.id, to: change.to.id, reason: change.reason, fade: change.fade,
            isDeferred: change.isDeferred, cause: cause, deltaL: change.deltaL, presence: situation.presence,
            mode: situation.mode, target: target, dwell: dwell)
    }
}

// MARK: - Mode

extension RotationService {
    /// The `Mode` setting, defaulting by the auto-appearance flag. Announced when it changes.
    private func currentMode() -> RotationMode {
        let setting = inputs.modeSetting()
        let isAuto = appearance.isAutoAppearance
        let mode = rotationMode(setting: setting, isAutoAppearance: isAuto)
        let event = RotationEvent.modeInEffect(mode: mode, setting: setting, isAutoAppearance: isAuto)
        // Compared as logged, as before: a change the log line wouldn't show isn't announced.
        if event.logLine != lastModeLine {
            lastModeLine = event.logLine
            onEvent(event)
        }
        return mode
    }
}
