import Foundation

// MARK: - Rotation
// Which video plays next, and when. A switch waits for Dwell (awake, unlocked time) and for a moment the Visibility
// allows (see `allowedTransition(for:)`); the next video is random among the unplayed-this-Pass videos of similar
// brightness, and a large brightness jump waits until nobody can see it. Every decision is here, with its state, so
// the app only gathers inputs (clock, RNG, settings, appearance, Visibility) and applies the switch.

enum RotationMode: String, CaseIterable {
    case all
    case light
    case dark
    case dynamic
}

enum Appearance: String {
    case light
    case dark
}

enum RotationRules {
    /// The largest mean-luminance difference a switch may make while anyone could see it.
    static let brightnessBand = 0.08
    /// With fewer videos, aiming `dynamic` at the Target brightness would leave too little to rotate: it acts as `all`.
    static let minimumForDaylight = 4
    /// `dynamic` picks at random among unplayed videos this close to the Target brightness, in rank.
    static let targetWindow = 0.15
    /// Further than this from the Target brightness, in rank, the Current video goes at the next Unseen or Veiled
    /// moment without waiting for Dwell. Wide enough that dusk is followed by ordinary Dwell switches.
    static let offTarget = 0.4
    /// Exactly 0.08 apart is within the band, whatever the floating-point rounding.
    static let tolerance = 1e-9
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
    let half: Appearance
    switch mode {
    case .all, .dynamic: return videos
    case .light: half = .light
    case .dark: half = .dark
    }
    let median = medianLuminance(of: videos)
    return videos.filter { half == .dark ? $0.meanLuminance <= median : $0.meanLuminance >= median }
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
    let others = candidates.filter { $0.name != current?.name }
    var unplayed = others.filter { !played.contains($0.name) }
    let startsPass = unplayed.isEmpty
    if startsPass { unplayed = others }
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

// MARK: - Target brightness

/// Each video's place from darkest (0) to brightest (1), evenly spaced whatever the luminance gaps, so the Target
/// brightness means the same with any library. Ties go by name so the order is stable; a lone video sits at 0.5.
func brightnessRanks(_ videos: [EligibleVideo]) -> [String: Double] {
    let sorted = videos.sorted { ($0.meanLuminance, $0.name) < ($1.meanLuminance, $1.name) }
    let last = Double(max(sorted.count - 1, 1))
    let pairs = sorted.enumerated().map { ($1.name, sorted.count == 1 ? 0.5 : Double($0) / last) }
    return Dictionary(pairs) { first, _ in first }
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

enum SwitchReason: String {
    case firstVideo = "first-video"
    case currentRemoved = "current-removed"
    case newVideo = "new-video"
    case modeChange = "mode-change"
    case offTarget = "off-target"
    case dwell
    case visibleFallback = "visible-fallback"
}

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
    var eligible: [EligibleVideo]
    var visibility: VisibilityState
    var mode: RotationMode
    /// Daylight, used as the Target brightness (a rank) when `followsDaylight`.
    var daylight: Double
    var isPowerSaving = false

    /// The videos the Mode allows right now.
    var candidates: [EligibleVideo] { modeCandidates(eligible, mode: mode) }

    /// `dynamic` with enough videos to aim at the Target brightness; otherwise it acts as `all`.
    var followsDaylight: Bool { mode == .dynamic && eligible.count >= RotationRules.minimumForDaylight }

    func isPreferred(_ video: EligibleVideo) -> Bool {
        guard followsDaylight else { return candidates.contains { $0.name == video.name } }
        guard let rank = brightnessRanks(eligible)[video.name] else { return true }
        return abs(rank - daylight) <= RotationRules.offTarget + RotationRules.tolerance
    }

    func eligible(named name: String) -> EligibleVideo? { eligible.first { $0.name == name } }
}

extension VisibilityInputs {
    /// Asleep, locked or switched away: not awake, unlocked time, so Dwell doesn't count.
    var isAwayFromDesk: Bool { areScreensAsleep || isLocked || isSessionInactive }
}

// MARK: - Rotation state

/// The Current video, the Pass, the videos waiting to play next and the Dwell. Each decision takes the situation and
/// returns what to do, having already moved to the state that follows, so the app only applies the outcome.
struct RotationState {
    private(set) var current: EligibleVideo?
    private(set) var dwell = Dwell()
    /// Shortens every minimum Dwell for a manual test; 1 otherwise.
    let dwellScale: Double
    private var played: Set<String> = []
    /// Newly added videos, in the order they arrived: each plays at the next allowed switch point.
    private var pendingNew: [String] = []
    private var known: Set<String>
    private var lastEligible: Set<String> = []
    private var desk = VisibilityInputs()
    /// The Current video was newly added: it plays whatever the Mode, so being outside the preferred half doesn't cut
    /// its Dwell short.
    private var isCurrentNew = false

    /// `present`: the folder's videos at launch. They join the Rotation as their Analysis finishes, not as new videos.
    init(present: Set<String>, dwellScale: Double = 1) {
        known = present
        self.dwellScale = dwellScale
    }

    /// Lock, screen sleep and session changes stop and start Dwell. Occlusion doesn't: working in an opaque app is
    /// still awake, unlocked time.
    mutating func apply(_ event: VisibilityEvent, at now: TimeInterval) {
        desk.apply(event)
        dwell.advance(to: now, isCounting: !desk.isAwayFromDesk)
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
        dwell.advance(to: situation.now, isCounting: !desk.isAwayFromDesk)
        noteLibrary(situation.eligible)
        guard let previous = current else { return startRotation(situation, using: &rng) }
        guard let current = situation.eligible(named: previous.name) else {
            return replaceRemoved(previous, situation, using: &rng)
        }
        // A re-analysed video keeps its place with its new luminance.
        self.current = current
        guard !situation.isPowerSaving else { return .stay }
        let allowed = allowedTransition(for: situation.visibility)
        // An off-Mode video (`Mode` edit, or far from the Target brightness) goes at the next Unseen or Veiled moment,
        // without Dwell.
        let isModeChange = isOffMode(current, situation) && situation.visibility != .visible
        guard isModeChange || dwell.elapsed >= minimumDwell(for: situation.visibility) else { return .stay }
        if let next = nextNewVideo(in: situation) {
            guard allowed.allowsBrightnessJump || isWithinBand(next, current) else { return .waitingForUnseen }
            return commit(
                (next, startsPass: false), from: current, reason: .newVideo, fade: allowed.crossfade,
                situation: situation)
        }
        let reason: SwitchReason = isModeChange ? (situation.followsDaylight ? .offTarget : .modeChange)
            : situation.visibility == .visible ? .visibleFallback : .dwell
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

    /// `dynamic`: random among unplayed-this-Pass videos within the target window; else the video nearest the Target
    /// brightness, unplayed first, which may replay one rather than leave the target (a small library has wide
    /// gaps). Without `allowsBigJump`, only videos within the band of `current` and no further from the target
    /// count, so a Visible or Veiled switch only ever walks toward the target. Nil when nothing is allowed.
    private func pickNearTarget(
        from current: EligibleVideo?,
        _ situation: RotationSituation,
        allowsBigJump: Bool,
        using rng: inout some RandomNumberGenerator
    ) -> (video: EligibleVideo, startsPass: Bool)? {
        let ranks = brightnessRanks(situation.eligible)
        let distance = { (video: EligibleVideo) in abs((ranks[video.name] ?? 0.5) - situation.daylight) }
        var others = situation.eligible.filter { $0.name != current?.name }
        var unplayed = Set(others.map(\.name)).subtracting(played)
        let startsPass = unplayed.isEmpty
        if startsPass { unplayed = Set(others.map(\.name)) }
        if let current, !allowsBigJump {
            let limit = ranks[current.name].map { abs($0 - situation.daylight) } ?? .infinity
            others = others.filter { isWithinBand($0, current) && distance($0) <= limit + RotationRules.tolerance }
        }
        let window = RotationRules.targetWindow + RotationRules.tolerance
        let near = others.filter { unplayed.contains($0.name) && distance($0) <= window }
        if let pick = near.randomElement(using: &rng) { return (pick, startsPass) }
        let nearest = others.min {
            (distance($0), unplayed.contains($0.name) ? 0 : 1, $0.name)
                < (distance($1), unplayed.contains($1.name) ? 0 : 1, $1.name)
        }
        return nearest.map { ($0, startsPass) }
    }

    private func nextNewVideo(in situation: RotationSituation) -> EligibleVideo? {
        pendingNew.first.flatMap(situation.eligible(named:))
    }

    private func minimumDwell(for state: VisibilityState) -> TimeInterval {
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
        let first = situation.followsDaylight
            ? pick(from: nil, situation, allowsBigJump: true, using: &rng)?.video
            : situation.candidates.randomElement(using: &rng)
        guard let next = nextNewVideo(in: situation) ?? first else {
            return .stay
        }
        return commit(
            (next, startsPass: true), from: nil, reason: .firstVideo, fade: Crossfade.quickDuration,
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
            pick, from: removed, reason: .currentRemoved, fade: Crossfade.quickDuration, situation: situation)
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
            from: previous, to: next, reason: reason, fade: fade, isDeferred: situation.isPowerSaving))
    }
}
