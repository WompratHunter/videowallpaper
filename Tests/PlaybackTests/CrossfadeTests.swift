import Foundation
@testable import Playback
import Testing

// MARK: - Crossfade tests

private let videoA = URL(fileURLWithPath: "/w/a.mp4")
private let videoB = URL(fileURLWithPath: "/w/b.mp4")
private let videoC = URL(fileURLWithPath: "/w/c.mp4")

// A fade still in progress is one whose tear-down drops an incoming player; `interrupt() == []` means only one
// player is left.

/// A crossfade from A that has started loading B.
private func loadingB(at now: TimeInterval = 0) -> (Crossfade, Int) {
    var fade = Crossfade()
    let actions = fade.request(videoB, duration: 5, current: videoA, isPlaying: true, now: now)
    guard case .load(let id, _)? = actions.first else {
        Issue.record("expected a load, got \(actions)")
        return (fade, -1)
    }
    return (fade, id)
}

private func fadingB() -> (Crossfade, Int) {
    var (fade, id) = loadingB()
    _ = fade.incomingReady(id: id, now: 1)
    return (fade, id)
}

@Test func crossfadeRequest() {
    var cut = Crossfade()
    #expect(cut.request(videoB, duration: 0, current: videoA, isPlaying: true, now: 0) == [.cut(videoB)])
    #expect(cut.interrupt().isEmpty)

    // Nobody sees a paused or torn-down player, so a fade would only cost a second decoder.
    var paused = Crossfade()
    #expect(paused.request(videoB, duration: 5, current: videoA, isPlaying: false, now: 0) == [.cut(videoB)])

    var same = Crossfade()
    #expect(same.request(videoA, duration: 5, current: videoA, isPlaying: true, now: 0).isEmpty)

    var fade = Crossfade()
    let actions = fade.request(videoB, duration: 5, current: videoA, isPlaying: true, now: 0)
    guard case .load(_, let url)? = actions.first else { Issue.record("expected a load, got \(actions)"); return }
    #expect(url == videoB)
    #expect(actions.count == 1)
    #expect(fade.interrupt() == [.dropIncoming])
}

@Test func crossfadeHappyPath() {
    var (fade, id) = loadingB()
    #expect(fade.incomingReady(id: id, now: 1) == [.animate(id: id, duration: 5)])
    #expect(fade.animationFinished(id: id) == [.promote(videoB)])
    #expect(fade.interrupt().isEmpty)
    #expect(fade.animationFinished(id: id).isEmpty)

    // A stale readiness or finish from an earlier fade is ignored.
    var (other, oldID) = loadingB()
    _ = other.interrupt()
    let next = other.request(videoC, duration: 20, current: videoA, isPlaying: true, now: 0)
    guard case .load(let newID, _)? = next.first else { Issue.record("expected a load, got \(next)"); return }
    #expect(newID != oldID, "every fade gets a fresh id")
    #expect(other.incomingReady(id: oldID, now: 1).isEmpty)
    #expect(other.incomingReady(id: newID, now: 1) == [.animate(id: newID, duration: 20)])
    #expect(other.animationFinished(id: oldID).isEmpty)
}

@Test func crossfadeRetarget() {
    // Same target again (e.g. another folder event): nothing changes.
    var (same, _) = loadingB()
    #expect(same.request(videoB, duration: 5, current: videoA, isPlaying: true, now: 2).isEmpty)

    // A different target while still loading: the incoming player is replaced, nothing has shown yet.
    var (retarget, oldID) = loadingB()
    let actions = retarget.request(videoC, duration: 5, current: videoA, isPlaying: true, now: 2)
    guard actions.count == 2, actions[0] == .dropIncoming, case .load(let newID, let url) = actions[1] else {
        Issue.record("expected drop then load, got \(actions)"); return
    }
    #expect(url == videoC)
    #expect(newID != oldID, "the replacement load has a new id")

    // The target reverts to the Current video while loading: drop the incoming, keep playing.
    var (revert, _) = loadingB()
    #expect(revert.request(videoA, duration: 5, current: videoA, isPlaying: true, now: 2) == [.dropIncoming])
    #expect(revert.interrupt().isEmpty)

    // A different target mid-fade waits for this fade to finish, then fades on from the new Current video.
    var (queued, id) = fadingB()
    #expect(queued.request(videoC, duration: 5, current: videoA, isPlaying: true, now: 2).isEmpty)
    let finish = queued.animationFinished(id: id)
    guard finish.count == 2, finish[0] == .promote(videoB), case .load(_, let next) = finish[1] else {
        Issue.record("expected promote then load, got \(finish)"); return
    }
    #expect(next == videoC)

    // The target reverts to the fading video before it finishes: the queued one is forgotten.
    var (reverted, revertedID) = fadingB()
    _ = reverted.request(videoC, duration: 5, current: videoA, isPlaying: true, now: 2)
    #expect(reverted.request(videoB, duration: 5, current: videoA, isPlaying: true, now: 3).isEmpty)
    #expect(reverted.animationFinished(id: revertedID) == [.promote(videoB)])

    // A cut requested mid-fade wins at once; the cut itself replaces both players.
    var (cut, _) = fadingB()
    #expect(cut.request(videoC, duration: 0, current: videoA, isPlaying: true, now: 2) == [.cut(videoC)])
    #expect(cut.interrupt().isEmpty)
}

@Test func crossfadeInterruption() {
    // Recovery, Low Power Mode or any other tear-down: the incoming player goes with the outgoing one, and the
    // rebuild that follows re-picks the video.
    var (loading, _) = loadingB()
    #expect(loading.interrupt() == [.dropIncoming])
    #expect(loading.interrupt().isEmpty)
    var (fading, _) = fadingB()
    #expect(fading.interrupt() == [.dropIncoming])
    #expect(fading.interrupt().isEmpty)
    var idle = Crossfade()
    #expect(idle.interrupt().isEmpty)

    // A queued target is forgotten too; the rebuild re-picks from the folder.
    var (queued, id) = fadingB()
    _ = queued.request(videoC, duration: 5, current: videoA, isPlaying: true, now: 2)
    _ = queued.interrupt()
    #expect(queued.animationFinished(id: id).isEmpty)

    // Occlusion or screens-asleep pause: nobody can see the fade, so it completes at once and the
    // incoming video becomes Current (and is paused with it).
    var (pausedLoading, _) = loadingB()
    #expect(pausedLoading.pause() == [.promote(videoB)])
    #expect(pausedLoading.interrupt().isEmpty)
    var (pausedFading, pausedID) = fadingB()
    #expect(pausedFading.pause() == [.promote(videoB)])
    #expect(pausedFading.animationFinished(id: pausedID).isEmpty)
    var idlePause = Crossfade()
    #expect(idlePause.pause().isEmpty)

    // Paused with a target queued: the last request wins, as a cut.
    var (pausedQueued, _) = fadingB()
    _ = pausedQueued.request(videoC, duration: 5, current: videoA, isPlaying: true, now: 2)
    #expect(pausedQueued.pause() == [.cut(videoC)])
}

@Test func crossfadeFailure() {
    var (failed, id) = loadingB()
    // The outgoing video is healthy, so it carries on rather than going through Recovery for someone else's file.
    #expect(failed.incomingFailed(id: id) == [.abandon(videoB)])
    #expect(failed.interrupt().isEmpty)
    var (staleFail, staleID) = loadingB()
    _ = staleFail.interrupt()
    #expect(staleFail.incomingFailed(id: staleID).isEmpty)
    var (failedFading, fadingID) = fadingB()
    #expect(failedFading.incomingFailed(id: fadingID) == [.abandon(videoB)])
    #expect(failedFading.animationFinished(id: fadingID).isEmpty)

    // Never ready for display: given up after the timeout, rather than cut to in plain view.
    var (slow, _) = loadingB(at: 100)
    #expect(slow.tick(now: 100 + Crossfade.readyTimeout - 1).isEmpty)
    #expect(slow.tick(now: 100 + Crossfade.readyTimeout) == [.abandon(videoB)])
    #expect(slow.interrupt().isEmpty)

    // A fade whose finish never arrives is completed by the tick, so two decoders never run on indefinitely.
    var (stuck, _) = fadingB()
    #expect(stuck.tick(now: 1 + 5 + Crossfade.readyTimeout - 1).isEmpty)
    #expect(stuck.tick(now: 1 + 5 + Crossfade.readyTimeout) == [.promote(videoB)])
    #expect(stuck.interrupt().isEmpty)
}
