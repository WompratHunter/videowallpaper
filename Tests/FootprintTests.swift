import Foundation

// MARK: - Footprint tests: original desktop pictures, restore

func runFootprintTests() {
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

private func runOwnPictureTests() {
    check(own.contains(poster.path), "a Poster in Application Support is ours")
    check(own.contains(legacy.path), "the legacy Poster in the Wallpaper folder is ours")
    check(!own.contains(beach.path), "the user's picture is not ours")
    check(!own.contains(support + "/posters-old/x.jpg"), "a sibling folder with a shared prefix is not ours")
}

private func runRecordOriginalsTests() {
    // First run: every screen's picture is recorded.
    let first = originalsToRecord(existing: nil, current: ["A": beach, "B": city], ownPictures: own)
    checkEqual(first, OriginalPictures(screens: ["A": beach, "B": city]))

    // Later runs never overwrite: the screens now show the Poster, and a changed picture is not recorded either.
    let recorded = OriginalPictures(screens: ["A": beach, "B": city])
    checkEqual(originalsToRecord(existing: recorded, current: ["A": poster, "B": poster], ownPictures: own), nil)
    checkEqual(originalsToRecord(existing: recorded, current: ["A": city, "B": beach], ownPictures: own), nil)

    // A display connected later is added, keeping the existing entries.
    checkEqual(
        originalsToRecord(existing: recorded, current: ["A": poster, "C": city], ownPictures: own),
        OriginalPictures(screens: ["A": beach, "B": city, "C": city]))

    // A screen already showing our Poster (an install from before originals were recorded) has no known original.
    checkEqual(originalsToRecord(existing: nil, current: ["A": legacy, "B": beach], ownPictures: own),
               OriginalPictures(screens: ["B": beach]))
    checkEqual(originalsToRecord(existing: nil, current: ["A": legacy], ownPictures: own), nil)
    checkEqual(originalsToRecord(existing: nil, current: [:], ownPictures: own), nil)
}

private func plan(
    _ originals: OriginalPictures?, _ current: [String: DesktopPicture], missing: Set<String> = []
) -> [String: DesktopPicture] {
    restorePlan(originals: originals, current: current, ownPictures: own, fallback: fallback) { !missing.contains($0) }
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
    checkEqual(restorePlan(originals: nil, current: ["A": poster], ownPictures: own, fallback: nil) { _ in true }, [:])
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
