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
    /// With fewer videos, halving the Rotation for `dynamic` would leave too little to rotate.
    static let minimumForHalves = 4
    /// Exactly 0.08 apart is within the band, whatever the floating-point rounding.
    static let tolerance = 1e-9
}

/// The `Mode` setting, read live. Missing or unknown: `dynamic` when the appearance switches automatically, as
/// Apple's dynamic wallpapers do, otherwise `all`, so a fixed appearance isn't taken as a preference.
func rotationMode(setting: String?, isAutoAppearance: Bool) -> RotationMode {
    if let setting, let mode = RotationMode(rawValue: setting.lowercased()) { return mode }
    return isAutoAppearance ? .dynamic : .all
}

/// The videos the Mode prefers: the darker or brighter half by median luminance (a video at the median is in both),
/// or every video. `dynamic` follows the appearance and acts as `all` with fewer than four videos.
func modeCandidates(_ videos: [EligibleVideo], mode: RotationMode, appearance: Appearance) -> [EligibleVideo] {
    let half: Appearance
    switch mode {
    case .all: return videos
    case .light: half = .light
    case .dark: half = .dark
    case .dynamic:
        guard videos.count >= RotationRules.minimumForHalves else { return videos }
        half = appearance
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
    case dwell
    case visibleFallback = "visible-fallback"
}

struct RotationSwitch: Equatable {
    let from: EligibleVideo?
    let to: EligibleVideo
    let reason: SwitchReason
    let fade: TimeInterval

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
    var appearance: Appearance
    var isPowerSaving = false
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

    /// `present`: the folder's videos at launch. They join the Rotation as their Analysis finishes, not as new videos.
    init(present: Set<String>, dwellScale: Double = 1) {
        known = present
        self.dwellScale = dwellScale
    }

    /// Lock, screen sleep and session changes stop and start Dwell. Occlusion doesn't: working in an opaque app is
    /// still awake, unlocked time.
    mutating func apply(_ event: VisibilityEvent, at now: TimeInterval) {
        desk.apply(event)
        dwell.advance(to: now, isCounting: isAtDesk)
    }

    /// Whether the next Unseen or Veiled moment would switch, so the app samples window coverage for Veiled.
    func isSwitchPointNear(_ situation: RotationSituation) -> Bool {
        guard let current else { return false }
        let candidates = modeCandidates(situation.eligible, mode: situation.mode, appearance: situation.appearance)
        let isOffMode = !candidates.contains { $0.name == current.name }
        return isOffMode || dwell.elapsed >= minimumDwell(for: .veiled)
    }

    mutating func decide(
        _ situation: RotationSituation, using rng: inout some RandomNumberGenerator
    ) -> RotationOutcome {
        dwell.advance(to: situation.now, isCounting: isAtDesk)
        noteLibrary(situation.eligible)
        guard let previous = current else { return startRotation(situation, using: &rng) }
        guard let current = situation.eligible.first(where: { $0.name == previous.name }) else {
            return replaceRemoved(previous, situation, using: &rng)
        }
        // A re-analysed video keeps its place with its new luminance.
        self.current = current
        guard !situation.isPowerSaving else { return .stay }
        let allowed = allowedTransition(for: situation.visibility)
        let isDwellDone = dwell.elapsed >= minimumDwell(for: situation.visibility)
        if let next = pendingNew.first.flatMap({ name in situation.eligible.first { $0.name == name } }) {
            guard isDwellDone else { return .stay }
            guard allowed.allowsBrightnessJump || isWithinBand(next, current) else { return .waitingForUnseen }
            return commit(next, from: current, reason: .newVideo, fade: allowed.crossfade, startsPass: false)
        }
        let candidates = modeCandidates(situation.eligible, mode: situation.mode, appearance: situation.appearance)
        let isOffMode = !candidates.contains { $0.name == current.name }
        let reason: SwitchReason
        if isOffMode && situation.visibility != .visible {
            reason = .modeChange
        } else if isDwellDone {
            reason = situation.visibility == .visible ? .visibleFallback : .dwell
        } else {
            return .stay
        }
        let allowsJump = allowed.allowsBrightnessJump
        guard let pick = pickNext(
            from: current, candidates: candidates, played: played, allowsBigJump: allowsJump, using: &rng)
        else {
            let hasOthers = candidates.contains { $0.name != current.name }
            return hasOthers && !allowsJump ? .waitingForUnseen : .stay
        }
        return commit(pick.video, from: current, reason: reason, fade: allowed.crossfade, startsPass: pick.startsPass)
    }

    private var isAtDesk: Bool { !(desk.areScreensAsleep || desk.isLocked || desk.isSessionInactive) }

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
        let candidates = modeCandidates(situation.eligible, mode: situation.mode, appearance: situation.appearance)
        let next = pendingNew.first.flatMap { name in situation.eligible.first { $0.name == name } }
            ?? candidates.randomElement(using: &rng)
        guard let next else { return .stay }
        return commit(next, from: nil, reason: .firstVideo, fade: Crossfade.quickDuration, startsPass: true)
    }

    /// The Current video left the Rotation: switch at once, whatever the brightness, since the Poster covers the gap.
    private mutating func replaceRemoved(
        _ removed: EligibleVideo, _ situation: RotationSituation, using rng: inout some RandomNumberGenerator
    ) -> RotationOutcome {
        current = nil
        let candidates = modeCandidates(situation.eligible, mode: situation.mode, appearance: situation.appearance)
        let newVideo = pendingNew.first.flatMap { name in situation.eligible.first { $0.name == name } }
        let pick = newVideo.map { (video: $0, startsPass: false) }
            ?? pickNext(from: removed, candidates: candidates, played: played, allowsBigJump: true, using: &rng)
        guard let pick else { return .stay }
        return commit(
            pick.video, from: removed, reason: .currentRemoved, fade: Crossfade.quickDuration,
            startsPass: pick.startsPass)
    }

    private mutating func commit(
        _ next: EligibleVideo,
        from previous: EligibleVideo?,
        reason: SwitchReason,
        fade: TimeInterval,
        startsPass: Bool
    ) -> RotationOutcome {
        if startsPass { played = [] }
        played.insert(next.name)
        pendingNew.removeAll { $0 == next.name }
        current = next
        dwell.restart()
        return .switchTo(RotationSwitch(from: previous, to: next, reason: reason, fade: fade))
    }
}
