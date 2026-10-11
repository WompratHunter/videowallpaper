import Foundation
import SharedKernel

// MARK: - Rotation
// Which video plays next, and when. A switch waits for Dwell (awake, unlocked time) and for a moment the Presence
// allows (see `allowedTransition(for:)`); the next video is random among the unplayed-this-Pass videos of similar
// brightness, and a large brightness jump waits until nobody can see it. Every decision is here, with its state, so
// the app only gathers inputs (clock, RNG, settings, Daylight, Presence) and applies the switch.

public enum RotationMode: String, CaseIterable, Sendable {
    case all
    case light
    case dark
    case dynamic
}

/// The `Mode` setting, read live. Missing or unknown: `dynamic` when the appearance switches automatically, as
/// Apple's dynamic wallpapers do, otherwise `all`, so a fixed appearance isn't taken as a preference.
func rotationMode(setting: String?, isAutoAppearance: Bool) -> RotationMode {
    if let setting, let mode = RotationMode(rawValue: setting.lowercased()) { return mode }
    return isAutoAppearance ? .dynamic : .all
}

/// The videos the Mode allows: the darker or brighter half by median luminance (a video at the median is in both),
/// or every video. `dynamic` allows every video and aims its pick at the Target brightness instead.
func modeCandidates(_ videos: [EligibleVideo], mode: RotationMode) -> [EligibleVideo] {
    guard mode == .light || mode == .dark else { return videos }
    let median = medianLuminance(of: videos)
    return videos.filter { mode == .dark ? $0.meanLuminance <= median : $0.meanLuminance >= median }
}

private func medianLuminance(of videos: [EligibleVideo]) -> Double {
    let sorted = videos.map(\.meanLuminance).sorted()
    guard !sorted.isEmpty else { return 0 }
    let mid = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

func luminanceDistance(_ a: EligibleVideo, _ b: EligibleVideo) -> Double {
    abs(a.meanLuminance - b.meanLuminance)
}

func isWithinBand(_ a: EligibleVideo, _ b: EligibleVideo) -> Bool {
    luminanceDistance(a, b) <= RotationRules.brightnessBand + RotationRules.tolerance
}

/// Random among `candidates` not yet played this Pass (a new Pass starts once all have played) within the band of
/// `from`; else the nearest unplayed, only if `allowsBigJump`. Nil when there is nothing else, or nothing allowed.
func pickNext(
    from current: EligibleVideo?,
    candidates: [EligibleVideo],
    played: Set<String>,
    allowsBigJump: Bool,
    using rng: inout some RandomNumberGenerator
) -> (video: EligibleVideo, startsPass: Bool)? {
    let (unplayed, startsPass) = passPool(candidates.filter { $0.name != current?.name }, played: played)
    guard !unplayed.isEmpty else { return nil }
    guard let current else { return unplayed.randomElement(using: &rng).map { ($0, startsPass) } }
    if let pick = unplayed.filter({ isWithinBand($0, current) }).randomElement(using: &rng) {
        return (pick, startsPass)
    }
    guard allowsBigJump else { return nil }
    let nearest = unplayed.min {
        (luminanceDistance($0, current), $0.name) < (luminanceDistance($1, current), $1.name)
    }
    return nearest.map { ($0, startsPass) }
}

/// The videos among `others` still to play this Pass; once every one has played, a new Pass starts with them all.
func passPool(_ others: [EligibleVideo], played: Set<String>) -> (unplayed: [EligibleVideo], startsPass: Bool) {
    let unplayed = others.filter { !played.contains($0.name) }
    return unplayed.isEmpty ? (others, true) : (unplayed, false)
}

// MARK: - Dwell

/// Awake, unlocked time since the last switch. Time counts between samples only while the previous sample said
/// "counting", and a single step counts at most `maxStep`, so a sleep the app never heard about isn't Dwell.
struct Dwell {
    /// The 5 s tick with tolerance, and room for a late tick or two.
    static let maxStep: TimeInterval = 30

    private(set) var elapsed: TimeInterval = 0
    private var lastSample: TimeInterval?
    private var isCounting = true

    mutating func advance(to now: TimeInterval, isCounting next: Bool) {
        if let lastSample, isCounting { elapsed += min(max(0, now - lastSample), Self.maxStep) }
        lastSample = now
        isCounting = next
    }

    mutating func restart() {
        elapsed = 0
    }
}

// MARK: - Switch decision

struct RotationSwitch: Equatable {
    let from: EligibleVideo?
    let to: EligibleVideo
    let reason: SwitchReason
    let fade: TimeInterval
    /// Low Power Mode: the Rotation moves on, but no player is built until it ends; that rebuild plays `to`.
    let isDeferred: Bool

    var deltaL: Double? { from.map { luminanceDistance($0, to) } }
}

enum RotationOutcome: Equatable {
    case stay
    case switchTo(RotationSwitch)
    /// A switch is due but every allowed video is too far in brightness: it waits for an Unseen moment.
    case waitingForUnseen
}

/// Everything a decision reads, gathered by the app at decision time.
struct RotationSituation {
    var now: TimeInterval
    var eligible: [EligibleVideo] { didSet { ranks = brightnessRanks(eligible) } }
    var presence: Presence
    var mode: RotationMode
    /// Daylight, used as the Target brightness (a rank) when `followsDaylight`.
    var daylight: Double
    var isLowPowerMode: Bool
    /// Each eligible video's brightness rank, worked out once per decision.
    private(set) var ranks: [String: Double]

    init(
        now: TimeInterval,
        eligible: [EligibleVideo],
        presence: Presence,
        mode: RotationMode,
        daylight: Double,
        isLowPowerMode: Bool = false
    ) {
        self.now = now
        self.eligible = eligible
        self.presence = presence
        self.mode = mode
        self.daylight = daylight
        self.isLowPowerMode = isLowPowerMode
        ranks = brightnessRanks(eligible)
    }

    /// The videos the Mode allows right now.
    var candidates: [EligibleVideo] { modeCandidates(eligible, mode: mode) }

    /// `dynamic` with enough videos to aim at the Target brightness; otherwise it acts as `all`.
    var followsDaylight: Bool { mode == .dynamic && eligible.count >= RotationRules.minimumForDaylight }

    func isPreferred(_ video: EligibleVideo) -> Bool {
        guard followsDaylight else { return candidates.contains { $0.name == video.name } }
        guard let rank = ranks[video.name] else { return true }
        return abs(rank - daylight) <= RotationRules.offTarget + RotationRules.tolerance
    }

    func eligible(named name: String) -> EligibleVideo? { eligible.first { $0.name == name } }
}

/// Whether the user is away from the desk (see `AwayFromDesk`): asleep, locked or switched away is not awake,
/// unlocked time, so Dwell doesn't count.
struct DeskState: Equatable {
    var areScreensAsleep = false
    var isSessionInactive = false
    var isLocked = false

    var isAway: Bool { areScreensAsleep || isLocked || isSessionInactive }

    mutating func apply(_ event: AwayFromDesk) {
        switch event {
        case .screensAsleep(let isOn): areScreensAsleep = isOn
        case .sessionInactive(let isOn): isSessionInactive = isOn
        case .locked(let isOn): isLocked = isOn
        }
    }
}

// MARK: - Rotation state

/// The Current video, the Pass, the videos waiting to play next and the Dwell. Each decision takes the situation and
/// returns what to do, having already moved to the state that follows, so the app only applies the outcome.
struct RotationState {
    private(set) var current: EligibleVideo?
    private(set) var dwell = Dwell()
    /// Shortens every minimum Dwell for a manual test; 1 otherwise.
    let dwellScale: Double
    private(set) var played: Set<String> = []
    /// Newly added videos, in the order they arrived: each plays at the next allowed switch point.
    private(set) var pendingNew: [String] = []
    private var known: Set<String>
    private(set) var lastEligible: Set<String> = []
    private var desk = DeskState()
    /// The Current video was newly added: it plays whatever the Mode, so being outside the preferred half doesn't cut
    /// its Dwell short.
    private var isCurrentNew = false

    /// `present`: the folder's videos at launch. They join the Rotation as their Analysis finishes, not as new videos.
    init(present: Set<String>, dwellScale: Double = 1) {
        known = present
        self.dwellScale = dwellScale
    }

    /// Lock, screen sleep and session changes stop and start Dwell. Occlusion isn't an input: working in an opaque
    /// app is still awake, unlocked time.
    mutating func apply(_ event: AwayFromDesk, at now: TimeInterval) {
        desk.apply(event)
        dwell.advance(to: now, isCounting: !desk.isAway)
    }

    /// Whether the next Unseen or Veiled moment would switch, so the app samples window coverage for Veiled.
    /// Nothing to switch to (a lone video) is never near, so the window list isn't read for nothing.
    func isSwitchPointNear(_ situation: RotationSituation) -> Bool {
        guard let current else { return false }
        let hasNext = nextNewVideo(in: situation) != nil || situation.candidates.contains { $0.name != current.name }
        return hasNext && (isOffMode(current, situation) || dwell.elapsed >= minimumDwell(for: .veiled))
    }

    mutating func decide(
        _ situation: RotationSituation, using rng: inout some RandomNumberGenerator
    ) -> RotationOutcome {
        dwell.advance(to: situation.now, isCounting: !desk.isAway)
        noteLibrary(situation.eligible)
        guard let previous = current else { return startRotation(situation, using: &rng) }
        guard let current = situation.eligible(named: previous.name) else {
            return replaceRemoved(previous, situation, using: &rng)
        }
        // A re-analysed video keeps its place with its new luminance.
        self.current = current
        guard !situation.isLowPowerMode else { return .stay }
        let allowed = allowedTransition(for: situation.presence)
        // An off-Mode video (`Mode` edit, or far from the Target brightness) goes at the next Unseen or Veiled moment,
        // without Dwell.
        let isModeChange = isOffMode(current, situation) && situation.presence != .visible
        guard isModeChange || dwell.elapsed >= minimumDwell(for: situation.presence) else { return .stay }
        if let next = nextNewVideo(in: situation) {
            guard allowed.allowsBrightnessJump || isWithinBand(next, current) else { return .waitingForUnseen }
            return commit(
                (next, startsPass: false), from: current, reason: .newVideo, fade: allowed.crossfade,
                situation: situation)
        }
        let reason: SwitchReason = isModeChange ? (situation.followsDaylight ? .offTarget : .modeChange)
            : situation.presence == .visible ? .visibleFallback : .dwell
        let allowsJump = allowed.allowsBrightnessJump
        guard let pick = pick(from: current, situation, allowsBigJump: allowsJump, using: &rng) else {
            let hasOthers = situation.candidates.contains { $0.name != current.name }
            return hasOthers && !allowsJump ? .waitingForUnseen : .stay
        }
        return commit(pick, from: current, reason: reason, fade: allowed.crossfade, situation: situation)
    }

    private func isOffMode(_ current: EligibleVideo, _ situation: RotationSituation) -> Bool {
        !isCurrentNew && !situation.isPreferred(current)
    }

    private func nextNewVideo(in situation: RotationSituation) -> EligibleVideo? {
        pendingNew.first.flatMap(situation.eligible(named:))
    }

    func minimumDwell(for state: Presence) -> TimeInterval {
        allowedTransition(for: state).minimumDwell * dwellScale
    }

    /// Newly eligible names (not present at launch, or gone and back) queue to play next, newest first within one
    /// change; videos that left drop out of the Pass and the queue.
    private mutating func noteLibrary(_ eligible: [EligibleVideo]) {
        let names = Set(eligible.map(\.name))
        let added = eligible.filter { !known.contains($0.name) }
            .sorted { ($0.modified, $1.name) > ($1.modified, $0.name) }
        pendingNew += added.map(\.name)
        known.subtract(lastEligible.subtracting(names))
        known.formUnion(names)
        lastEligible = names
        pendingNew.removeAll { !names.contains($0) }
        played.formIntersection(names)
    }

    /// Nothing is playing yet: the first video plays at once, a newly added one first.
    private mutating func startRotation(
        _ situation: RotationSituation, using rng: inout some RandomNumberGenerator
    ) -> RotationOutcome {
        guard let next = nextNewVideo(in: situation)
            ?? pick(from: nil, situation, allowsBigJump: true, using: &rng)?.video
        else { return .stay }
        return commit(
            (next, startsPass: true), from: nil, reason: .firstVideo, fade: RotationRules.quickFade,
            situation: situation)
    }

    /// The Current video left the Rotation: switch at once, whatever the brightness, since the Poster covers the gap.
    private mutating func replaceRemoved(
        _ removed: EligibleVideo, _ situation: RotationSituation, using rng: inout some RandomNumberGenerator
    ) -> RotationOutcome {
        current = nil
        let pick = nextNewVideo(in: situation).map { (video: $0, startsPass: false) }
            ?? pick(from: removed, situation, allowsBigJump: true, using: &rng)
        guard let pick else { return .stay }
        return commit(
            pick, from: removed, reason: .currentRemoved, fade: RotationRules.quickFade, situation: situation)
    }

    private mutating func commit(
        _ pick: (video: EligibleVideo, startsPass: Bool),
        from previous: EligibleVideo?,
        reason: SwitchReason,
        fade: TimeInterval,
        situation: RotationSituation
    ) -> RotationOutcome {
        let next = pick.video
        if pick.startsPass { played = [] }
        played.insert(next.name)
        isCurrentNew = pendingNew.contains(next.name)
        pendingNew.removeAll { $0 == next.name }
        current = next
        dwell.restart()
        return .switchTo(RotationSwitch(
            from: previous, to: next, reason: reason, fade: fade, isDeferred: situation.isLowPowerMode))
    }
}

// MARK: - Pick

extension RotationState {
    /// Near the Target brightness in `dynamic`, else within the band among the Mode's candidates.
    private func pick(
        from current: EligibleVideo?,
        _ situation: RotationSituation,
        allowsBigJump: Bool,
        using rng: inout some RandomNumberGenerator
    ) -> (video: EligibleVideo, startsPass: Bool)? {
        guard situation.followsDaylight else {
            return pickNext(
                from: current, candidates: situation.candidates, played: played, allowsBigJump: allowsBigJump,
                using: &rng)
        }
        return pickNearTarget(from: current, situation, allowsBigJump: allowsBigJump, using: &rng)
    }

    /// `dynamic`: random among unplayed-this-Pass videos within the target window; else the unplayed video nearest
    /// the Target brightness, unless it would itself be off target (a small library has wide gaps), in which case the
    /// nearest video plays again. Without `allowsBigJump`, only videos within the band of `current` count, and from
    /// outside the window none further from the target, so a Visible or Veiled switch walks toward it.
    private func pickNearTarget(
        from current: EligibleVideo?,
        _ situation: RotationSituation,
        allowsBigJump: Bool,
        using rng: inout some RandomNumberGenerator
    ) -> (video: EligibleVideo, startsPass: Bool)? {
        let ranks = situation.ranks
        let distance = { (video: EligibleVideo) in abs((ranks[video.name] ?? 0.5) - situation.daylight) }
        var others = situation.eligible.filter { $0.name != current?.name }
        let pool = passPool(others, played: played)
        let unplayed = Set(pool.unplayed.map(\.name))
        let startsPass = pool.startsPass
        let window = RotationRules.targetWindow + RotationRules.tolerance
        if let current, !allowsBigJump {
            let fromCurrent = ranks[current.name].map { abs($0 - situation.daylight) } ?? .infinity
            let limit = max(fromCurrent + RotationRules.tolerance, window)
            others = others.filter { isWithinBand($0, current) && distance($0) <= limit }
        }
        let fresh = others.filter { unplayed.contains($0.name) }
        if let pick = fresh.filter({ distance($0) <= window }).randomElement(using: &rng) { return (pick, startsPass) }
        let byDistance = { (a: EligibleVideo, b: EligibleVideo) in (distance(a), a.name) < (distance(b), b.name) }
        let reach = RotationRules.offTarget + RotationRules.tolerance
        if let nearestFresh = fresh.min(by: byDistance), distance(nearestFresh) <= reach {
            return (nearestFresh, startsPass)
        }
        return others.min(by: byDistance).map { ($0, startsPass) }
    }
}
