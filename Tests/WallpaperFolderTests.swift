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

    checkEqual(newestVideo(in: ["old.mp4": start, "new.mp4": start.addingTimeInterval(5)]), "new.mp4")
    checkEqual(newestVideo(in: [:]), nil)
    runFolderChangeActionTests()
    runSettleTests()
    runFolderSettlerTests()
}

private func action(
    newest: URL?, current: URL?, exists: Bool, recovering: Bool = false, powerSaving: Bool = false
) -> FolderChangeAction {
    folderChangeAction(
        newest: newest, current: current, currentExists: exists, isRecovering: recovering,
        isPowerSaving: powerSaving)
}

private func runFolderChangeActionTests() {
    let rain = URL(fileURLWithPath: "/v/rain.mp4")
    let sea = URL(fileURLWithPath: "/v/sea.mp4")

    // Healthy playback keeps "newest wins".
    checkEqual(action(newest: rain, current: rain, exists: true), .keepPlaying)
    checkEqual(action(newest: sea, current: rain, exists: true), .switchTo(sea))
    checkEqual(action(newest: sea, current: nil, exists: false), .switchTo(sea))

    // The playing file vanished but another video is there: a logged Recovery that rebuilds now (the settle
    // check already debounced the burst of folder events).
    checkEqual(action(newest: sea, current: rain, exists: false), .rebuildNow(.fileMissing))

    // No eligible video left: rest on the Poster (not a failure).
    checkEqual(action(newest: nil, current: rain, exists: false), .restNoVideo)
    checkEqual(action(newest: nil, current: nil, exists: false, recovering: true), .restNoVideo)

    // A video is back (returned or newly added) while Recovery is pending or resting: rebuild now, not after backoff.
    checkEqual(action(newest: rain, current: rain, exists: true, recovering: true), .rebuildNow(.videoAvailable))
    checkEqual(action(newest: sea, current: rain, exists: true, recovering: true), .rebuildNow(.videoAvailable))

    // In Low Power Mode nothing is built; leaving it re-picks the newest video.
    checkEqual(action(newest: sea, current: rain, exists: true, powerSaving: true), .holdForPower)
    checkEqual(action(newest: sea, current: rain, exists: false, powerSaving: true), .holdForPower)
    checkEqual(action(newest: nil, current: rain, exists: false, powerSaving: true), .holdForPower)
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

private func runFolderSettlerTests() {
    // Videos present at launch play at once; the launch snapshot is the first check's baseline.
    var settler = FolderSettler(trusting: ["rain.mp4": file(500), "half.mp4": file(100)])
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
