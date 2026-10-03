import Foundation

// MARK: - Wallpaper folder tests

func runWallpaperFolderTests() {
    check(isWallpaperVideo(named: "beach.mp4"), "mp4 is a video")
    check(isWallpaperVideo(named: "City.MOV"), "extension match ignores case")
    check(isWallpaperVideo(named: "clip.m4v"), "m4v is a video")
    check(!isWallpaperVideo(named: ".poster.jpg"), "the Poster export is not a video")
    check(!isWallpaperVideo(named: ".DS_Store"), "Finder metadata is not a video")
    check(!isWallpaperVideo(named: ".hidden.mp4"), "hidden files are ignored")
    check(!isWallpaperVideo(named: "notes.txt"), "other files are ignored")

    let start = Date(timeIntervalSince1970: 0)
    let before = videoListing(of: ["beach.mp4": start])
    checkEqual(videoListing(of: ["beach.mp4": start, ".poster.jpg": start, ".DS_Store": start]), before)
    check(videoListing(of: ["beach.mp4": start, "city.mov": start]) != before, "a new video is a change")
    check(videoListing(of: [:]) != before, "a removed video is a change")
    check(videoListing(of: ["beach.mp4": start.addingTimeInterval(1)]) != before, "a replaced video is a change")

    runFolderChangeActionTests()
    runSettleTests()
    runFolderSettlerTests()
}

private func action(
    toPlay: URL?, current: URL?, exists: Bool, recovering: Bool = false, powerSaving: Bool = false
) -> FolderChangeAction {
    folderChangeAction(
        toPlay: toPlay, current: current, currentExists: exists, isRecovering: recovering,
        isPowerSaving: powerSaving)
}

private func runFolderChangeActionTests() {
    let rain = URL(fileURLWithPath: "/v/rain.mp4")
    let sea = URL(fileURLWithPath: "/v/sea.mp4")

    // Healthy playback switches only to a different video to play.
    checkEqual(action(toPlay: rain, current: rain, exists: true), .keepPlaying)
    checkEqual(action(toPlay: sea, current: rain, exists: true), .switchTo(sea))
    checkEqual(action(toPlay: sea, current: nil, exists: false), .switchTo(sea))

    // The playing file vanished but another video is there: a logged Recovery that rebuilds now (the settle
    // check already debounced the burst of folder events).
    checkEqual(action(toPlay: sea, current: rain, exists: false), .rebuildNow(.fileMissing))

    // No eligible video left: rest on the Poster (not a failure).
    checkEqual(action(toPlay: nil, current: rain, exists: false), .restNoVideo)
    checkEqual(action(toPlay: nil, current: nil, exists: false, recovering: true), .restNoVideo)

    // A video is back (returned or newly added) while Recovery is pending or resting: rebuild now, not after backoff.
    checkEqual(action(toPlay: rain, current: rain, exists: true, recovering: true), .rebuildNow(.videoAvailable))
    checkEqual(action(toPlay: sea, current: rain, exists: true, recovering: true), .rebuildNow(.videoAvailable))

    // In Low Power Mode nothing is built; leaving it rebuilds the video to play.
    checkEqual(action(toPlay: sea, current: rain, exists: true, powerSaving: true), .holdForPower)
    checkEqual(action(toPlay: sea, current: rain, exists: false, powerSaving: true), .holdForPower)
    checkEqual(action(toPlay: nil, current: rain, exists: false, powerSaving: true), .holdForPower)
}

private func file(_ size: Int64, _ seconds: TimeInterval = 0) -> VideoFile {
    VideoFile(size: size, modified: Date(timeIntervalSince1970: seconds))
}

private func runSettleTests() {
    let earlier = ["done.mp4": file(500), "copying.mp4": file(100), "empty.mp4": file(0), "gone.mp4": file(9)]
    let later = ["done.mp4": file(500), "copying.mp4": file(300), "empty.mp4": file(0), "new.mp4": file(50, 7)]
    let settled = settledVideos(earlier: earlier, later: later)
    checkEqual(Set(settled.keys), ["done.mp4"])
    checkEqual(settled["done.mp4"], Date(timeIntervalSince1970: 0))
}

private func outcome(changed: Bool, again: Bool) -> SettleOutcome {
    SettleOutcome(isReadyChanged: changed, needsAnotherCheck: again)
}

private let launchTime = Date(timeIntervalSince1970: 1000)

private func runLaunchSettleTests() {
    // Untouched for the check interval: settled at launch, so a normal launch plays without waiting. Written in
    // the last 3 s (still being copied) or empty: not loaded until the first check finds it stable.
    let snapshot = [
        "rain.mp4": file(500, 900), "edge.mp4": file(500, 997), "copying.mp4": file(100, 999),
        "empty.mp4": file(0, 900)
    ]
    var settler = FolderSettler(launch: snapshot, now: launchTime)
    checkEqual(Set(settler.ready.keys), ["edge.mp4", "rain.mp4"])
    check(!settler.noteEvent(snapshot), "the launch check is already pending")
    // Finished copying by the first check: loaded then.
    let later = ["rain.mp4": file(500, 900), "edge.mp4": file(500, 997), "copying.mp4": file(100, 999)]
    checkEqual(settler.check(later), outcome(changed: true, again: false))
    checkEqual(Set(settler.ready.keys), ["copying.mp4", "edge.mp4", "rain.mp4"])
}

private func runFolderSettlerTests() {
    runLaunchSettleTests()

    // A copy that kept its source's date is trusted at launch, but the first check drops it if it grew.
    var settler = FolderSettler(launch: ["rain.mp4": file(500), "half.mp4": file(100)], now: launchTime)
    checkEqual(Set(settler.ready.keys), ["half.mp4", "rain.mp4"])
    check(!settler.noteEvent(["rain.mp4": file(500)]), "the launch check is already pending")
    // A copy that was still running at launch is dropped by that first check.
    checkEqual(settler.check(["rain.mp4": file(500), "half.mp4": file(200)]), outcome(changed: true, again: true))
    checkEqual(Set(settler.ready.keys), ["rain.mp4"])
    checkEqual(settler.check(["rain.mp4": file(500), "half.mp4": file(200)]), outcome(changed: true, again: false))
    checkEqual(Set(settler.ready.keys), ["half.mp4", "rain.mp4"])

    // A copy starts: the first event schedules a check; more events while it is pending don't.
    check(settler.noteEvent(["rain.mp4": file(500), "sea.mp4": file(10)]), "first event schedules a check")
    check(!settler.noteEvent(["rain.mp4": file(500), "sea.mp4": file(20)]), "pending check is not rescheduled")

    // Still growing 3 s later: not loaded, check again.
    checkEqual(settler.check(["rain.mp4": file(500), "sea.mp4": file(40)]), outcome(changed: true, again: true))
    checkEqual(Set(settler.ready.keys), ["rain.mp4"])

    // Unchanged across two checks: settled and loadable; nothing left to watch.
    checkEqual(settler.check(["rain.mp4": file(500), "sea.mp4": file(40, 3)]), outcome(changed: true, again: false))
    checkEqual(Set(settler.ready.keys), ["rain.mp4", "sea.mp4"])
    checkEqual(settler.ready["sea.mp4"], Date(timeIntervalSince1970: 3))

    // An event that changes nothing (e.g. the Poster export) does not disturb the player.
    check(settler.noteEvent(["rain.mp4": file(500), "sea.mp4": file(40, 3)]), "event schedules a check")
    checkEqual(settler.check(["rain.mp4": file(500), "sea.mp4": file(40, 3)]), outcome(changed: false, again: false))

    // A deletion drops the file once checked.
    check(settler.noteEvent(["sea.mp4": file(40, 3)]), "deletion schedules a check")
    checkEqual(settler.check(["sea.mp4": file(40, 3)]), outcome(changed: true, again: false))
    checkEqual(Set(settler.ready.keys), ["sea.mp4"])

    // An empty placeholder that never grows is neither loaded nor polled forever.
    check(settler.noteEvent(["sea.mp4": file(40, 3)]), "an event schedules a check")
    checkEqual(settler.check(["sea.mp4": file(40, 3), "stub.mp4": file(0)]), outcome(changed: false, again: true))
    checkEqual(settler.check(["sea.mp4": file(40, 3), "stub.mp4": file(0)]), outcome(changed: false, again: false))
    checkEqual(Set(settler.ready.keys), ["sea.mp4"])
}
