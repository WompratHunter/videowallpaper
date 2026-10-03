import Foundation

// MARK: - Footprint tests: Poster storage, original desktop pictures, restore

func runFootprintTests() {
    runPosterNameTests()
    runStalePosterTests()
    runOwnPictureTests()
    runRecordOriginalsTests()
    runRestorePlanTests()
    runOriginalsCodingTests()
}

private let support = "/Users/me/Library/Application Support/VideoWallpaper"
private let own = OwnPictures(
    posterDirectory: support + "/posters", legacyPoster: "/Users/me/Movies/LiveWallpaper/.poster.jpg")
private let plain = DesktopPictureOptions()
private let beach = DesktopPicture(path: "/Users/me/Pictures/beach.jpg", options: plain)
private let city = DesktopPicture(
    path: "/System/Library/Desktop Pictures/City.heic",
    options: DesktopPictureOptions(scaling: 3, allowsClipping: true))
private let poster = DesktopPicture(path: support + "/posters/poster-0123456789abcdef.jpg", options: plain)
private let legacy = DesktopPicture(path: "/Users/me/Movies/LiveWallpaper/.poster.jpg", options: plain)
private let fallback = DesktopPicture(path: "/System/Library/CoreServices/DefaultDesktop.heic", options: plain)

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
    checkEqual(stalePosters(in: [keep, gone, ".DS_Store", "readme.txt"], keeping: [keep]), [gone])
    checkEqual(stalePosters(in: [keep], keeping: [keep]), [])
    checkEqual(stalePosters(in: [], keeping: [keep]), [])
}

private func runOwnPictureTests() {
    check(own.contains(poster.path), "a Poster in Application Support is ours")
    check(own.contains(legacy.path), "the legacy Poster in the Wallpaper folder is ours")
    check(!own.contains(beach.path), "the user's picture is not ours")
    check(!own.contains(support + "/posters-old/x.jpg"), "a sibling folder with a shared prefix is not ours")
}

private func runRecordOriginalsTests() {
    // First run: every screen's picture is recorded.
    let first = originalsToRecord(existing: nil, current: ["A": beach, "B": city], own: own)
    checkEqual(first, OriginalPictures(screens: ["A": beach, "B": city]))

    // Later runs never overwrite: the screens now show the Poster, and a changed picture is not recorded either.
    let recorded = OriginalPictures(screens: ["A": beach, "B": city])
    checkEqual(originalsToRecord(existing: recorded, current: ["A": poster, "B": poster], own: own), nil)
    checkEqual(originalsToRecord(existing: recorded, current: ["A": city, "B": beach], own: own), nil)

    // A display connected later is added, keeping the existing entries.
    checkEqual(
        originalsToRecord(existing: recorded, current: ["A": poster, "C": city], own: own),
        OriginalPictures(screens: ["A": beach, "B": city, "C": city]))

    // A screen already showing our Poster (an install from before originals were recorded) has no known original.
    checkEqual(originalsToRecord(existing: nil, current: ["A": legacy, "B": beach], own: own),
               OriginalPictures(screens: ["B": beach]))
    checkEqual(originalsToRecord(existing: nil, current: ["A": legacy], own: own), nil)
    checkEqual(originalsToRecord(existing: nil, current: [:], own: own), nil)
}

private func plan(
    _ originals: OriginalPictures?, _ current: [String: DesktopPicture], missing: Set<String> = []
) -> [String: DesktopPicture] {
    restorePlan(originals: originals, current: current, own: own, fallback: fallback) { !missing.contains($0) }
}

private func runRestorePlanTests() {
    let recorded = OriginalPictures(screens: ["A": beach, "B": city])

    // Each screen showing our Poster gets its own original back, options included.
    checkEqual(plan(recorded, ["A": poster, "B": poster]), ["A": beach, "B": city])
    checkEqual(plan(recorded, ["A": legacy]), ["A": beach])

    // A picture the user chose since install is left alone.
    checkEqual(plan(recorded, ["A": city, "B": poster]), ["B": city])

    // A screen with no record borrows another screen's original, the first by screen key so it is stable.
    checkEqual(plan(recorded, ["C": poster]), ["C": beach])

    // Nothing recorded (an older install): the system default picture replaces our Poster.
    checkEqual(plan(nil, ["A": poster, "B": beach]), ["A": fallback])

    // An original that was deleted since cannot be restored: another screen's original, else the default picture.
    checkEqual(plan(recorded, ["A": poster], missing: [beach.path]), ["A": city])
    checkEqual(plan(recorded, ["A": poster], missing: [beach.path, city.path]), ["A": fallback])
    checkEqual(restorePlan(originals: nil, current: ["A": poster], own: own, fallback: nil) { _ in true }, [:])
    checkEqual(plan(nil, ["A": poster], missing: [fallback.path]), [:])

    // Nothing of ours on screen: nothing to do.
    checkEqual(plan(recorded, ["A": beach, "B": city]), [:])
}

private func runOriginalsCodingTests() {
    let recorded = OriginalPictures(screens: [
        "A": beach,
        "B": DesktopPicture(
            path: city.path,
            options: DesktopPictureOptions(scaling: 1, allowsClipping: false, fillColor: [0, 0.5, 1, 1]))
    ])
    checkEqual(OriginalPictures(json: recorded.json()), recorded)
    checkEqual(OriginalPictures(json: Data("not json".utf8)), nil)
}
