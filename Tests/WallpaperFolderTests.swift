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
}

private func runFolderChangeActionTests() {
    let rain = URL(fileURLWithPath: "/v/rain.mp4")
    let sea = URL(fileURLWithPath: "/v/sea.mp4")

    // Healthy playback keeps "newest wins".
    checkEqual(folderChangeAction(newest: rain, current: rain, currentExists: true, isRecovering: false), .keepPlaying)
    checkEqual(folderChangeAction(newest: sea, current: rain, currentExists: true, isRecovering: false), .switchTo(sea))
    checkEqual(folderChangeAction(newest: sea, current: nil, currentExists: false, isRecovering: false), .switchTo(sea))

    // The playing file vanished but another video is there: a logged Recovery that rebuilds promptly.
    checkEqual(
        folderChangeAction(newest: sea, current: rain, currentExists: false, isRecovering: false),
        .rebuildSoon(.fileMissing))

    // No eligible video left: rest on the Poster (not a failure).
    checkEqual(folderChangeAction(newest: nil, current: rain, currentExists: false, isRecovering: false), .restNoVideo)
    checkEqual(folderChangeAction(newest: nil, current: nil, currentExists: false, isRecovering: true), .restNoVideo)

    // A video is back (returned or newly added) while Recovery is pending or resting: rebuild now, not after backoff.
    checkEqual(
        folderChangeAction(newest: rain, current: rain, currentExists: true, isRecovering: true),
        .rebuildSoon(.videoAvailable))
    checkEqual(
        folderChangeAction(newest: sea, current: rain, currentExists: true, isRecovering: true),
        .rebuildSoon(.videoAvailable))
}
