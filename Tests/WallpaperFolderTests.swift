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
}
