import Foundation
@testable import Rotation
import SharedKernel
import Testing

// MARK: - Rotation tests: Daylight
// The Target brightness in `dynamic`, on the user's four videos (see RotationTests.swift). Ranks: ff7 0, lucyna a
// third, maomao two thirds, capybara 1.

/// `dynamic` in the dark, at Daylight 0.
private func night(
    _ now: TimeInterval, _ presence: Presence, _ eligible: [EligibleVideo] = userVideos
) -> RotationSituation {
    situation(at: now, eligible, presence, mode: .dynamic, daylight: 0)
}

/// `dynamic` aims at the Target brightness (Daylight as a rank). A Current video far from it switches at the next
/// Unseen or Veiled moment without waiting for Dwell; while anyone can see, the pick only walks toward the target.
@Test func dynamicAimsAtTheTargetBrightness() {
    var rng = SeededGenerator(state: 7)
    // Launch at night: the darkest video.
    var launch = RotationState(present: Set(names(userVideos)))
    #expect(switched(launch.decide(night(0, .visible), using: &rng))?.to == ff7)

    // Night falls on maomao (two thirds up): off target. Visible: it waits, but asks for Veiled sampling.
    var state = playing(maomao, mode: .dynamic, daylight: 2.0 / 3)
    #expect(state.decide(night(10, .visible), using: &rng) == .stay)
    #expect(state.isSwitchPointNear(night(10, .visible)), "an off-target video asks for Veiled sampling")
    // Veiled: no big jump, so one step toward the target within the band (lucyna), not ff7.
    let step = switched(state.decide(night(15, .veiled), using: &rng))
    #expect(step?.reason == .offTarget)
    #expect(step?.to == lucyna)
    // A third from the target is near enough: no early switch.
    #expect(state.decide(night(20, .unseen), using: &rng) == .stay)
    // At the next Dwell switch, Veiled: the only in-band video (maomao) is further from the target, so it waits.
    tick(&state, from: 20, until: 20 + twentyMinutes)
    #expect(state.decide(night(20 + twentyMinutes, .veiled), using: &rng) == .waitingForUnseen)
    // Unseen: the darkest video, a big jump.
    #expect(switched(state.decide(night(20 + twentyMinutes, .unseen), using: &rng))?.to == ff7)
    // The only unplayed video (capybara) would itself be off target: lucyna, the nearest, plays again instead.
    tick(&state, from: 20 + twentyMinutes, until: 20 + 2 * twentyMinutes)
    #expect(switched(state.decide(night(20 + 2 * twentyMinutes, .unseen), using: &rng))?.to == lucyna)
}

/// Midday, an empty window, a small library and a newly added video (dusk at a rank no video sits near is below).
@Test func dynamicAtTheEdges() {
    var rng = SeededGenerator(state: 8)
    // Midday on ff7: capybara is the target.
    var day = playing(ff7, mode: .dynamic, daylight: 0)
    let toDay = switched(day.decide(situation(at: 5, userVideos, .unseen, mode: .dynamic, daylight: 1), using: &rng))
    #expect(toDay?.reason == .offTarget)
    #expect(toDay?.to == capybara)

    // An empty window: the nearest unplayed video within reach (ff7) beats replaying a nearer played one (lucyna).
    var evening = playing(lucyna, mode: .dynamic, daylight: 1.0 / 3)
    tick(&evening, from: 0, until: twentyMinutes)
    let dynamicAt = { (now: TimeInterval, target: Double) in
        situation(at: now, userVideos, .unseen, mode: .dynamic, daylight: target)
    }
    #expect(switched(evening.decide(dynamicAt(twentyMinutes, 2.0 / 3), using: &rng))?.to == maomao)
    tick(&evening, from: twentyMinutes, until: 2 * twentyMinutes)
    #expect(switched(evening.decide(dynamicAt(2 * twentyMinutes, 0.2), using: &rng))?.to == ff7)

    // Visible, already inside the window: another video in the window may play though a little further from the
    // target (mid at 0.15 from it, lucyna at 0.1); walking toward the target only binds outside the window.
    let five = userVideos + [video("mid.mp4", 0.17)]
    var settled = playing(lucyna, among: five, mode: .dynamic, daylight: 0.25)
    tick(&settled, from: 0, until: 60 * 60, five)
    let variety = switched(settled.decide(
        situation(at: 60 * 60, five, .visible, mode: .dynamic, daylight: 0.35), using: &rng))
    #expect(variety?.to.name == "mid.mp4")
    #expect(variety?.reason == .visibleFallback)

    // Fewer than four videos: dynamic acts as all, so night doesn't force a switch.
    let three = [capybara, lucyna, maomao]
    var small = playing(capybara, among: three, mode: .dynamic, daylight: 1)
    #expect(small.decide(night(5, .unseen, three), using: &rng) == .stay)

    // A newly added video plays next even at night, and keeps its full Dwell though it's far from the target.
    var fresh = playing(lucyna, mode: .dynamic, daylight: 1.0 / 3)
    let brightNew = video("sunny.mp4", 0.5, modified: 100)
    let withNew = userVideos + [brightNew]
    _ = fresh.decide(night(5, .visible, withNew), using: &rng)
    tick(&fresh, from: 5, until: twentyMinutes, withNew)
    #expect(switched(fresh.decide(night(twentyMinutes, .unseen, withNew), using: &rng))?.to == brightNew)
    #expect(fresh.decide(night(twentyMinutes + 60, .unseen, withNew), using: &rng) == .stay)
    #expect(
        !fresh.isSwitchPointNear(night(twentyMinutes + 60, .visible, withNew)), "a new video's Dwell isn't cut short")
}

/// Dusk at a rank no video sits near (0.5): the nearest unplayed video, not a replay or the far end, whatever the RNG.
@Test(arguments: UInt64(0)..<10)
func duskPicksAMiddleVideo(seed: UInt64) {
    var rng = SeededGenerator(state: seed)
    var dusk = playing(ff7, mode: .dynamic, daylight: 0)
    let pick = switched(dusk.decide(
        situation(at: 5, userVideos, .unseen, mode: .dynamic, daylight: 0.5), using: &rng))?.to
    #expect(pick == lucyna || pick == maomao, "dusk picks a middle video, got \(pick?.name ?? "none")")
}
