@testable import Core
import Foundation
import Rotation
import SharedKernel

// MARK: - Rotation tests
// The user's four videos and their measured luminance anchor the expectations: lucyna and maomao are 0.016 apart,
// ff7 (0.037) and capybara (0.299) are more than 0.08 from every other video, so reaching or leaving them needs Unseen.

func runRotationTests() {
    runModeTests()
    runPickTests()
    runDwellTests()
    runSchedulingTests()
    runLibraryChangeTests()
    runDaylightTargetTests()
    runAllowedTransitionTests()
}

/// SplitMix64: a deterministic RNG so every pick in these tests is reproducible.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

func video(_ name: String, _ luminance: Double, modified: TimeInterval = 0) -> EligibleVideo {
    EligibleVideo(
        id: VideoID(name), version: Version(size: 1, modified: Date(timeIntervalSince1970: modified)),
        meanLuminance: luminance)
}

let capybara = video("capybara.mp4", 0.299)
let ff7 = video("ff7.mp4", 0.037)
let lucyna = video("lucyna.mp4", 0.161)
let maomao = video("maomao.mp4", 0.177)
let userVideos = [capybara, ff7, lucyna, maomao]

func names(_ videos: [EligibleVideo]) -> [String] { videos.map(\.name).sorted() }

func situation(
    at now: TimeInterval,
    _ eligible: [EligibleVideo] = userVideos,
    _ visibility: Presence = .visible,
    mode: RotationMode = .all,
    daylight: Double = 0,
    isPowerSaving: Bool = false
) -> RotationSituation {
    RotationSituation(
        now: now, eligible: eligible, visibility: visibility, mode: mode, daylight: daylight,
        isPowerSaving: isPowerSaving)
}

func switched(_ outcome: RotationOutcome) -> RotationSwitch? {
    if case .switchTo(let change) = outcome { return change }
    return nil
}

/// A state already playing `start`, its launch pick, at time 0.
func playing(
    _ start: EligibleVideo,
    among eligible: [EligibleVideo] = userVideos,
    alsoPresent: [String] = [],
    mode: RotationMode = .all,
    daylight: Double = 0
) -> RotationState {
    let state = RotationState(present: Set(eligible.map(\.name) + alsoPresent))
    for seed in UInt64(0)..<200 {
        var attempt = state
        var rng = SeededGenerator(state: seed)
        let launch = situation(at: 0, eligible, mode: mode, daylight: daylight)
        if switched(attempt.decide(launch, using: &rng))?.to == start { return attempt }
    }
    fatalError("no seed starts on \(start.name)")
}

let twentyMinutes: TimeInterval = 20 * 60
private let oneHour: TimeInterval = 60 * 60

/// Visible ticks at the desk every 5 s, short of `end`: Dwell grows, and the decision at `end` is the caller's.
func tick(
    _ state: inout RotationState,
    from start: TimeInterval,
    until end: TimeInterval,
    _ eligible: [EligibleVideo] = userVideos
) {
    var rng = SeededGenerator(state: 99)
    var now = start + 5
    while now < end {
        _ = state.decide(situation(at: now, eligible, .visible), using: &rng)
        now += 5
    }
}

// MARK: - Mode

private func runModeTests() {
    checkEqual(rotationMode(setting: nil, isAutoAppearance: true), .dynamic)
    checkEqual(rotationMode(setting: nil, isAutoAppearance: false), .all)
    checkEqual(rotationMode(setting: "dark", isAutoAppearance: false), .dark)
    checkEqual(rotationMode(setting: "Light", isAutoAppearance: true), .light)
    checkEqual(rotationMode(setting: "sepia", isAutoAppearance: true), .dynamic)

    // The user's median is 0.169: ff7 and lucyna are the darker half, maomao and capybara the brighter.
    checkEqual(names(modeCandidates(userVideos, mode: .dark)), ["ff7.mp4", "lucyna.mp4"])
    checkEqual(names(modeCandidates(userVideos, mode: .light)), ["capybara.mp4", "maomao.mp4"])
    checkEqual(names(modeCandidates(userVideos, mode: .all)), names(userVideos))
    // dynamic narrows by Daylight at the pick, not by halves.
    checkEqual(names(modeCandidates(userVideos, mode: .dynamic)), names(userVideos))
    // An odd count puts the median video in both halves.
    let five = userVideos + [video("mid.mp4", 0.17)]
    checkEqual(names(modeCandidates(five, mode: .dark)), ["ff7.mp4", "lucyna.mp4", "mid.mp4"])
    checkEqual(names(modeCandidates(five, mode: .light)), ["capybara.mp4", "maomao.mp4", "mid.mp4"])

    // Brightness rank: darkest 0 to brightest 1, evenly spaced, whatever the luminance gaps.
    let ranks = brightnessRanks(userVideos)
    checkEqual(ranks["ff7.mp4"], 0)
    checkEqual(ranks["capybara.mp4"], 1)
    check(abs((ranks["lucyna.mp4"] ?? 0) - 1.0 / 3) < 1e-9 && abs((ranks["maomao.mp4"] ?? 0) - 2.0 / 3) < 1e-9,
          "lucyna and maomao are a third and two thirds up")
}

// MARK: - Pick

private func runPickTests() {
    var rng = SeededGenerator(state: 1)
    // Band: from lucyna, only maomao is within 0.08, whatever the RNG.
    for _ in 0..<50 {
        let pick = pickNext(from: lucyna, candidates: userVideos, played: [], allowsBigJump: false, using: &rng)
        checkEqual(pick?.video, maomao)
    }
    // Exactly 0.08 apart is within the band.
    let edge = video("edge.mp4", 0.161 + 0.08)
    checkEqual(
        pickNext(from: lucyna, candidates: [lucyna, edge], played: [], allowsBigJump: false, using: &rng)?.video, edge)
    // Unseen-only big jump: nothing is near capybara or ff7, so no pick unless a big jump is allowed.
    check(pickNext(from: capybara, candidates: userVideos, played: [], allowsBigJump: false, using: &rng) == nil,
          "capybara has no video within the band")
    check(pickNext(from: ff7, candidates: userVideos, played: [], allowsBigJump: false, using: &rng) == nil,
          "ff7 has no video within the band")
    checkEqual(
        pickNext(from: capybara, candidates: userVideos, played: [], allowsBigJump: true, using: &rng)?.video, maomao)
    checkEqual(pickNext(from: ff7, candidates: userVideos, played: [], allowsBigJump: true, using: &rng)?.video, lucyna)
    // An in-band video is preferred even when a big jump is allowed.
    checkEqual(
        pickNext(from: maomao, candidates: userVideos, played: [], allowsBigJump: true, using: &rng)?.video, lucyna)
    // No repeat within a Pass: maomao played, so from lucyna the nearest unplayed (ff7) when Unseen.
    let afterMaomao = pickNext(
        from: lucyna, candidates: userVideos, played: ["maomao.mp4", "lucyna.mp4"], allowsBigJump: true, using: &rng)
    checkEqual(afterMaomao?.video, ff7)
    checkEqual(afterMaomao?.startsPass, false)
    // Played maomao while Visible: nothing allowed, rather than a repeat.
    check(pickNext(
        from: lucyna, candidates: userVideos, played: ["maomao.mp4"], allowsBigJump: false, using: &rng) == nil,
          "a played video is not repeated within the Pass")
    // Every other video played: a new Pass starts.
    let allPlayed = Set(names(userVideos))
    let newPass = pickNext(from: lucyna, candidates: userVideos, played: allPlayed, allowsBigJump: false, using: &rng)
    checkEqual(newPass?.video, maomao)
    checkEqual(newPass?.startsPass, true)
    // Only the Current video: nothing to switch to.
    check(pickNext(from: lucyna, candidates: [lucyna], played: [], allowsBigJump: true, using: &rng) == nil,
          "a lone video never switches to itself")
}

// MARK: - Dwell

private func runDwellTests() {
    var dwell = Dwell()
    dwell.advance(to: 0, isCounting: true)
    dwell.advance(to: 5, isCounting: true)
    checkEqual(dwell.elapsed, 5)
    // Locked from 5 s to 600 s: none of it counts.
    dwell.advance(to: 5, isCounting: false)
    dwell.advance(to: 600, isCounting: true)
    checkEqual(dwell.elapsed, 5)
    // A sleep the app never heard of (a 2 h gap between ticks) counts as one late tick at most.
    dwell.advance(to: 600 + 7200, isCounting: true)
    checkEqual(dwell.elapsed, 5 + Dwell.maxStep)
    dwell.restart()
    checkEqual(dwell.elapsed, 0)

    // Through the state: screens asleep and locked pause Dwell. Occlusion (working in an opaque app) isn't an input,
    // so it can't.
    var state = playing(lucyna)
    var rng = SeededGenerator(state: 3)
    tick(&state, from: 0, until: 600)
    state.apply(.locked(true), at: 600)
    checkEqual(state.dwell.elapsed, 600)
    _ = state.decide(situation(at: 620, userVideos, .unseen), using: &rng)
    state.apply(.screensAsleep(true), at: 625)
    state.apply(.locked(false), at: 3000)
    _ = state.decide(situation(at: 3020, userVideos, .unseen), using: &rng)
    checkEqual(state.dwell.elapsed, 600)
    state.apply(.screensAsleep(false), at: 3020)
    tick(&state, from: 3020, until: 3050)
    _ = state.decide(situation(at: 3050), using: &rng)
    checkEqual(state.dwell.elapsed, 630)
}

// MARK: - When to switch

private func runSchedulingTests() {
    var rng = SeededGenerator(state: 5)
    // Launch: the first eligible video plays at once.
    var launch = RotationState(present: Set(names(userVideos)))
    let first = switched(launch.decide(situation(at: 0), using: &rng))
    checkEqual(first?.reason, .firstVideo)
    check(first?.from == nil && first?.deltaL == nil, "the first video has no predecessor")

    // Under 20 min of Dwell nothing switches, even Unseen.
    var state = playing(lucyna)
    tick(&state, from: 0, until: twentyMinutes - 5)
    checkEqual(state.decide(situation(at: twentyMinutes - 5, userVideos, .unseen), using: &rng), .stay)
    // At 20 min, Veiled: a 5 s crossfade to the in-band video.
    tick(&state, from: twentyMinutes - 5, until: twentyMinutes)
    let veiled = switched(state.decide(situation(at: twentyMinutes, userVideos, .veiled), using: &rng))
    checkEqual(veiled?.to, maomao)
    checkEqual(veiled?.reason, .dwell)
    checkEqual(veiled?.fade, 5)
    check(abs((veiled?.deltaL ?? 1) - 0.016) < 1e-9, "ΔL is the luminance difference")
    checkEqual(state.dwell.elapsed, 0)

    // Visible only: nothing at 20 min, a 20 s crossfade at 1 h.
    var visible = playing(lucyna)
    tick(&visible, from: 0, until: twentyMinutes)
    checkEqual(visible.decide(situation(at: twentyMinutes), using: &rng), .stay)
    tick(&visible, from: twentyMinutes, until: oneHour)
    let fallback = switched(visible.decide(situation(at: oneHour), using: &rng))
    checkEqual(fallback?.reason, .visibleFallback)
    checkEqual(fallback?.fade, 20)
    checkEqual(fallback?.to, maomao)
    runBrightnessJumpTests()
}

/// Large brightness jumps, a full Pass and Low Power Mode, on the user's four videos.
private func runBrightnessJumpTests() {
    var rng = SeededGenerator(state: 6)
    // From capybara nothing is within the band: Veiled waits, Unseen takes the nearest (maomao).
    var bright = playing(capybara)
    tick(&bright, from: 0, until: oneHour)
    checkEqual(bright.decide(situation(at: oneHour), using: &rng), .waitingForUnseen)
    checkEqual(bright.decide(situation(at: oneHour, userVideos, .veiled), using: &rng), .waitingForUnseen)
    let jump = switched(bright.decide(situation(at: oneHour, userVideos, .unseen), using: &rng))
    checkEqual(jump?.to, maomao)
    checkEqual(jump?.fade, 5)

    // Reaching ff7 needs Unseen: after maomao, lucyna; after both, only ff7 or capybara remain, both far.
    var dark = playing(maomao)
    tick(&dark, from: 0, until: twentyMinutes)
    checkEqual(switched(dark.decide(situation(at: twentyMinutes, userVideos, .veiled), using: &rng))?.to, lucyna)
    tick(&dark, from: twentyMinutes, until: 2 * twentyMinutes)
    checkEqual(dark.decide(situation(at: 2 * twentyMinutes, userVideos, .veiled), using: &rng), .waitingForUnseen)
    checkEqual(switched(dark.decide(situation(at: 2 * twentyMinutes, userVideos, .unseen), using: &rng))?.to, ff7)

    // No repeat in a Pass: switching while Unseen visits all four before any repeats.
    var pass = playing(capybara)
    var seen = [capybara.name]
    var now: TimeInterval = 0
    for _ in 0..<3 {
        tick(&pass, from: now, until: now + twentyMinutes)
        now += twentyMinutes
        if let change = switched(pass.decide(situation(at: now, userVideos, .unseen), using: &rng)) {
            seen.append(change.to.name)
        }
    }
    checkEqual(seen.sorted(), names(userVideos))

    // Low Power Mode: no switch, however long the Dwell.
    var power = playing(lucyna)
    tick(&power, from: 0, until: oneHour)
    checkEqual(power.decide(situation(at: oneHour, userVideos, .unseen, isPowerSaving: true), using: &rng), .stay)

}

// MARK: - Folder changes

private func runLibraryChangeTests() {
    var rng = SeededGenerator(state: 11)
    // A newly added video plays next, at the next allowed switch point, ahead of the random pick.
    var state = playing(lucyna)
    let added = video("new.mp4", 0.2, modified: 100)
    let withNew = userVideos + [added]
    checkEqual(state.decide(situation(at: 5, withNew, .unseen), using: &rng), .stay)
    tick(&state, from: 5, until: twentyMinutes, withNew)
    let next = switched(state.decide(situation(at: twentyMinutes, withNew, .veiled), using: &rng))
    checkEqual(next?.to, added)
    checkEqual(next?.reason, .newVideo)
    // A new video too far in brightness waits for Unseen rather than letting another video go first.
    var waiting = playing(lucyna)
    let brightNew = video("bright.mp4", 0.6, modified: 100)
    let withBright = userVideos + [brightNew]
    _ = waiting.decide(situation(at: 5, withBright), using: &rng)
    tick(&waiting, from: 5, until: twentyMinutes, withBright)
    checkEqual(waiting.decide(situation(at: twentyMinutes, withBright, .veiled), using: &rng), .waitingForUnseen)
    checkEqual(switched(waiting.decide(situation(at: twentyMinutes, withBright, .unseen), using: &rng))?.to, brightNew)
    // A video present at launch but analysed later joins the Rotation without jumping the queue: were it new, the
    // far-off late video would hold the switch until Unseen.
    var launch = playing(lucyna, alsoPresent: ["late.mp4"])
    let withLate = userVideos + [video("late.mp4", 0.9)]
    _ = launch.decide(situation(at: 5, withLate), using: &rng)
    tick(&launch, from: 5, until: twentyMinutes, withLate)
    checkEqual(switched(launch.decide(situation(at: twentyMinutes, withLate, .veiled), using: &rng))?.to, maomao)

    // Removing the Current video switches at once, Visible and with no Dwell, by the nearest-brightness rule.
    var removal = playing(lucyna)
    let removed = switched(removal.decide(situation(at: 5, [capybara, ff7, maomao]), using: &rng))
    checkEqual(removed?.reason, .currentRemoved)
    checkEqual(removed?.to, maomao)
    checkEqual(removed?.from, lucyna)
    checkEqual(removed?.isDeferred, false)
    // In Low Power Mode the replacement is still chosen, but deferred: it plays when Low Power Mode ends.
    var lowPower = playing(lucyna)
    let deferred = switched(lowPower.decide(situation(at: 5, [capybara, maomao], isPowerSaving: true), using: &rng))
    checkEqual(deferred?.to, maomao)
    checkEqual(deferred?.isDeferred, true)
    checkEqual(lowPower.current, maomao)
    // The last video removed: nothing to play.
    var last = playing(lucyna, among: [lucyna])
    checkEqual(last.decide(situation(at: 5, []), using: &rng), .stay)
    check(last.current == nil, "no Current video once the folder is empty")
    // A video added to an empty Rotation plays at once.
    checkEqual(switched(last.decide(situation(at: 10, [maomao]), using: &rng))?.reason, .firstVideo)
    runSwitchPointTests()
}

/// Veiled is sampled from the window list only when a switch could follow.
private func runSwitchPointTests() {
    // A lone video has nowhere to go, so a long Dwell doesn't ask for the window list.
    var lone = playing(lucyna, among: [lucyna])
    tick(&lone, from: 0, until: oneHour, [lucyna])
    check(!lone.isSwitchPointNear(situation(at: oneHour, [lucyna])), "a lone video is never near a switch")
    var pair = playing(lucyna, among: [lucyna, maomao])
    tick(&pair, from: 0, until: twentyMinutes + 10, [lucyna, maomao])
    check(pair.isSwitchPointNear(situation(at: twentyMinutes, [lucyna, maomao])), "Dwell met with somewhere to go")
}

private func runAllowedTransitionTests() {
    let quick = AllowedTransition(crossfade: 5, minimumDwell: 20 * 60, allowsBrightnessJump: false)
    let quickWithJump = AllowedTransition(crossfade: 5, minimumDwell: 20 * 60, allowsBrightnessJump: true)
    let fallback = AllowedTransition(crossfade: 20, minimumDwell: 60 * 60, allowsBrightnessJump: false)
    // A big brightness jump only when nobody watches; Veiled is still seen through the glass.
    checkEqual(allowedTransition(for: .unseen), quickWithJump)
    checkEqual(allowedTransition(for: .veiled), quick)
    // Visible only via the slow fallback after an hour.
    checkEqual(allowedTransition(for: .visible), fallback)
}
