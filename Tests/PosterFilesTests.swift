import Foundation

// MARK: - Poster file tests: names and pruning

func runPosterFilesTests() {
    runPosterNameTests()
    runStalePosterTests()
}

private func runPosterNameTests() {
    let file = VideoFile(size: 1_000, modified: Date(timeIntervalSince1970: 1_700_000_000))
    let name = posterFileName(forVideoAt: "/v/rain.mp4", file: file)
    checkEqual(name, posterFileName(forVideoAt: "/v/rain.mp4", file: file))
    check(isPosterFileName(name), "a generated name is recognised as a Poster: \(name)")
    check(name.hasSuffix(".jpg") && !name.hasPrefix("."), "Poster names are visible JPEGs: \(name)")
    // Golden value: the name must not change between runs (Swift's Hasher is seeded per process).
    checkEqual(name, "poster-1b423921114e5bb3.jpg")
    check(name != posterFileName(forVideoAt: "/v/sea.mp4", file: file), "another path gets another Poster")
    check(
        name != posterFileName(forVideoAt: "/v/rain.mp4", file: VideoFile(size: 1_001, modified: file.modified)),
        "a replaced file (new size) gets a new Poster")
    check(
        name != posterFileName(
            forVideoAt: "/v/rain.mp4", file: VideoFile(size: 1_000, modified: file.modified.addingTimeInterval(1))),
        "a touched file (new mtime) gets a new Poster")
    check(!isPosterFileName(".poster.jpg"), "the legacy Poster is not one of the new names")
    check(!isPosterFileName("notes.txt"), "other files are not Posters")
}

private func runStalePosterTests() {
    let keep = "poster-0000000000000001.jpg"
    let gone = "poster-0000000000000002.jpg"
    let current = "poster-0000000000000003.jpg"
    checkEqual(
        stalePosters(in: [keep, gone, current, ".DS_Store", "readme.txt"], keeping: [keep], current: current), [gone])
    checkEqual(stalePosters(in: [keep], keeping: [keep], current: current), [])
    checkEqual(stalePosters(in: [], keeping: [keep], current: current), [])
    // An unreadable Wallpaper folder lists no videos; the Current Poster (the desktop picture) must still survive.
    checkEqual(stalePosters(in: [gone, current], keeping: [], current: current), [gone])
}
