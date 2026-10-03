import Foundation

// MARK: - Crossfade tests

private let videoA = URL(fileURLWithPath: "/w/a.mp4")
private let videoB = URL(fileURLWithPath: "/w/b.mp4")
private let videoC = URL(fileURLWithPath: "/w/c.mp4")

// A fade still in progress is one whose tear-down drops an incoming player; `interrupt() == []` means only one
// player is left.
func runCrossfadeTests() {
    runCrossfadeRequestTests()
    runCrossfadeHappyPathTests()
    runCrossfadeRetargetTests()
    runCrossfadeInterruptionTests()
    runCrossfadeFailureTests()
}

/// A crossfade from A that has started loading B.
private func loadingB(at now: TimeInterval = 0) -> (Crossfade, Int) {
    var fade = Crossfade()
    let actions = fade.request(videoB, duration: 5, current: videoA, isPlaying: true, now: now)
    guard case .load(let id, _)? = actions.first else {
        check(false, "expected a load, got \(actions)")
        return (fade, -1)
    }
    return (fade, id)
}

private func fadingB() -> (Crossfade, Int) {
    var (fade, id) = loadingB()
    _ = fade.incomingReady(id: id, now: 1)
    return (fade, id)
}

private func runCrossfadeRequestTests() {
    var cut = Crossfade()
    checkEqual(cut.request(videoB, duration: 0, current: videoA, isPlaying: true, now: 0), [.cut(videoB)])
    checkEqual(cut.interrupt(), [])

    // Nobody sees a paused or torn-down player, so a fade would only cost a second decoder.
    var paused = Crossfade()
    checkEqual(paused.request(videoB, duration: 5, current: videoA, isPlaying: false, now: 0), [.cut(videoB)])

    var same = Crossfade()
    checkEqual(same.request(videoA, duration: 5, current: videoA, isPlaying: true, now: 0), [])

    var fade = Crossfade()
    let actions = fade.request(videoB, duration: 5, current: videoA, isPlaying: true, now: 0)
    guard case .load(_, let url)? = actions.first else { return check(false, "expected a load, got \(actions)") }
    checkEqual(url, videoB)
    checkEqual(actions.count, 1)
    checkEqual(fade.interrupt(), [.dropIncoming])
}

private func runCrossfadeHappyPathTests() {
    var (fade, id) = loadingB()
    checkEqual(fade.incomingReady(id: id, now: 1), [.animate(id: id, duration: 5)])
    checkEqual(fade.animationFinished(id: id), [.promote(videoB)])
    checkEqual(fade.interrupt(), [])
    checkEqual(fade.animationFinished(id: id), [])

    // A stale readiness or finish from an earlier fade is ignored.
    var (other, oldID) = loadingB()
    _ = other.interrupt()
    let next = other.request(videoC, duration: 20, current: videoA, isPlaying: true, now: 0)
    guard case .load(let newID, _)? = next.first else { return check(false, "expected a load, got \(next)") }
    check(newID != oldID, "every fade gets a fresh id")
    checkEqual(other.incomingReady(id: oldID, now: 1), [])
    checkEqual(other.incomingReady(id: newID, now: 1), [.animate(id: newID, duration: 20)])
    checkEqual(other.animationFinished(id: oldID), [])
}

private func runCrossfadeRetargetTests() {
    // Same target again (e.g. another folder event): nothing changes.
    var (same, _) = loadingB()
    checkEqual(same.request(videoB, duration: 5, current: videoA, isPlaying: true, now: 2), [])

    // A different target while still loading: the incoming player is replaced, nothing has shown yet.
    var (retarget, oldID) = loadingB()
    let actions = retarget.request(videoC, duration: 5, current: videoA, isPlaying: true, now: 2)
    guard actions.count == 2, actions[0] == .dropIncoming, case .load(let newID, let url) = actions[1] else {
        return check(false, "expected drop then load, got \(actions)")
    }
    checkEqual(url, videoC)
    check(newID != oldID, "the replacement load has a new id")

    // The target reverts to the Current video while loading: drop the incoming, keep playing.
    var (revert, _) = loadingB()
    checkEqual(revert.request(videoA, duration: 5, current: videoA, isPlaying: true, now: 2), [.dropIncoming])
    checkEqual(revert.interrupt(), [])

    // A different target mid-fade waits for this fade to finish, then fades on from the new Current video.
    var (queued, id) = fadingB()
    checkEqual(queued.request(videoC, duration: 5, current: videoA, isPlaying: true, now: 2), [])
    let finish = queued.animationFinished(id: id)
    guard finish.count == 2, finish[0] == .promote(videoB), case .load(_, let next) = finish[1] else {
        return check(false, "expected promote then load, got \(finish)")
    }
    checkEqual(next, videoC)

    // The target reverts to the fading video before it finishes: the queued one is forgotten.
    var (reverted, revertedID) = fadingB()
    _ = reverted.request(videoC, duration: 5, current: videoA, isPlaying: true, now: 2)
    checkEqual(reverted.request(videoB, duration: 5, current: videoA, isPlaying: true, now: 3), [])
    checkEqual(reverted.animationFinished(id: revertedID), [.promote(videoB)])

    // A cut requested mid-fade wins at once; the cut itself replaces both players.
    var (cut, _) = fadingB()
    checkEqual(cut.request(videoC, duration: 0, current: videoA, isPlaying: true, now: 2), [.cut(videoC)])
    checkEqual(cut.interrupt(), [])
}

private func runCrossfadeInterruptionTests() {
    // Recovery, Low Power Mode or any other tear-down: the incoming player goes with the outgoing one, and the
    // rebuild that follows re-picks the video.
    var (loading, _) = loadingB()
    checkEqual(loading.interrupt(), [.dropIncoming])
    checkEqual(loading.interrupt(), [])
    var (fading, _) = fadingB()
    checkEqual(fading.interrupt(), [.dropIncoming])
    checkEqual(fading.interrupt(), [])
    var idle = Crossfade()
    checkEqual(idle.interrupt(), [])

    // A queued target is forgotten too; the rebuild re-picks from the folder.
    var (queued, id) = fadingB()
    _ = queued.request(videoC, duration: 5, current: videoA, isPlaying: true, now: 2)
    _ = queued.interrupt()
    checkEqual(queued.animationFinished(id: id), [])

    // Occlusion or screens-asleep pause: nobody can see the fade, so it completes at once and the
    // incoming video becomes Current (and is paused with it).
    var (pausedLoading, _) = loadingB()
    checkEqual(pausedLoading.pause(), [.promote(videoB)])
    checkEqual(pausedLoading.interrupt(), [])
    var (pausedFading, pausedID) = fadingB()
    checkEqual(pausedFading.pause(), [.promote(videoB)])
    checkEqual(pausedFading.animationFinished(id: pausedID), [])
    var idlePause = Crossfade()
    checkEqual(idlePause.pause(), [])

    // Paused with a target queued: the last request wins, as a cut.
    var (pausedQueued, _) = fadingB()
    _ = pausedQueued.request(videoC, duration: 5, current: videoA, isPlaying: true, now: 2)
    checkEqual(pausedQueued.pause(), [.cut(videoC)])
}

private func runCrossfadeFailureTests() {
    var (failed, id) = loadingB()
    // The outgoing video is healthy, so it carries on rather than going through Recovery for someone else's file.
    checkEqual(failed.incomingFailed(id: id), [.abandon(videoB)])
    checkEqual(failed.interrupt(), [])
    var (staleFail, staleID) = loadingB()
    _ = staleFail.interrupt()
    checkEqual(staleFail.incomingFailed(id: staleID), [])
    var (failedFading, fadingID) = fadingB()
    checkEqual(failedFading.incomingFailed(id: fadingID), [.abandon(videoB)])
    checkEqual(failedFading.animationFinished(id: fadingID), [])

    // Never ready for display: given up after the timeout, rather than cut to in plain view.
    var (slow, _) = loadingB(at: 100)
    checkEqual(slow.tick(now: 100 + Crossfade.readyTimeout - 1), [])
    checkEqual(slow.tick(now: 100 + Crossfade.readyTimeout), [.abandon(videoB)])
    checkEqual(slow.interrupt(), [])

    // A fade whose finish never arrives is completed by the tick, so two decoders never run on indefinitely.
    var (stuck, _) = fadingB()
    checkEqual(stuck.tick(now: 1 + 5 + Crossfade.readyTimeout - 1), [])
    checkEqual(stuck.tick(now: 1 + 5 + Crossfade.readyTimeout), [.promote(videoB)])
    checkEqual(stuck.interrupt(), [])
}
