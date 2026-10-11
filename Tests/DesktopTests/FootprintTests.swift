@testable import Desktop
import Foundation
import SharedKernel
import Testing

// MARK: - Footprint tests
// The user's own desktop pictures: which pictures are ours, what is recorded, the restore plan, and the record's JSON.

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

struct OwnPictureTests {
    @Test func aPosterInApplicationSupportIsOurs() {
        #expect(own.contains(poster.path))
    }

    @Test func theLegacyPosterInTheWallpaperFolderIsOurs() {
        #expect(own.contains(legacy.path))
    }

    @Test func theUsersPictureIsNotOurs() {
        #expect(!own.contains(beach.path))
    }

    @Test func aSiblingFolderWithASharedPrefixIsNotOurs() {
        #expect(!own.contains(support + "/posters-old/x.jpg"))
    }
}

struct RecordOriginalsTests {
    private let recorded = OriginalPictures(screens: ["A": beach, "B": city])

    @Test func theFirstRunRecordsEveryScreen() {
        #expect(originalsToRecord(existing: nil, current: ["A": beach, "B": city], ownPictures: own) == recorded)
    }

    /// Later runs never overwrite: the screens now show the Poster, and a changed picture is not recorded either.
    @Test func laterRunsNeverOverwrite() {
        #expect(originalsToRecord(existing: recorded, current: ["A": poster, "B": poster], ownPictures: own) == nil)
        #expect(originalsToRecord(existing: recorded, current: ["A": city, "B": beach], ownPictures: own) == nil)
    }

    @Test func aDisplayConnectedLaterIsAddedKeepingTheExistingEntries() {
        #expect(
            originalsToRecord(existing: recorded, current: ["A": poster, "C": city], ownPictures: own)
                == OriginalPictures(screens: ["A": beach, "B": city, "C": city]))
    }

    /// An install from before originals were recorded: a screen already showing our Poster has no known original.
    @Test func aScreenAlreadyShowingOurPosterIsNotRecorded() {
        #expect(
            originalsToRecord(existing: nil, current: ["A": legacy, "B": beach], ownPictures: own)
                == OriginalPictures(screens: ["B": beach]))
        #expect(originalsToRecord(existing: nil, current: ["A": legacy], ownPictures: own) == nil)
        #expect(originalsToRecord(existing: nil, current: [:], ownPictures: own) == nil)
    }
}

struct RestorePlanTests {
    private let recorded = OriginalPictures(screens: ["A": beach, "B": city])

    private func plan(
        _ originals: OriginalPictures?, _ current: [String: DesktopPicture], missing: Set<String> = []
    ) -> [String: DesktopPicture] {
        restorePlan(originals: originals, current: current, ownPictures: own, fallback: fallback) {
            !missing.contains($0)
        }
    }

    @Test func eachScreenShowingOurPosterGetsItsOwnOriginalBackWithItsOptions() {
        #expect(plan(recorded, ["A": poster, "B": poster]) == ["A": beach, "B": city])
        #expect(plan(recorded, ["A": legacy]) == ["A": beach])
    }

    @Test func aPictureTheUserChoseSinceInstallIsLeftAlone() {
        #expect(plan(recorded, ["A": city, "B": poster]) == ["B": city])
    }

    /// The first by screen key, so it is stable.
    @Test func aScreenWithNoRecordBorrowsAnotherScreensOriginal() {
        #expect(plan(recorded, ["C": poster]) == ["C": beach])
    }

    /// An older install recorded nothing.
    @Test func withNothingRecordedTheSystemDefaultReplacesOurPoster() {
        #expect(plan(nil, ["A": poster, "B": beach]) == ["A": fallback])
    }

    @Test func aDeletedOriginalFallsBackToAnotherScreensThenTheDefault() {
        #expect(plan(recorded, ["A": poster], missing: [beach.path]) == ["A": city])
        #expect(plan(recorded, ["A": poster], missing: [beach.path, city.path]) == ["A": fallback])
        let noFallback = restorePlan(originals: nil, current: ["A": poster], ownPictures: own, fallback: nil) { _ in
            true
        }
        #expect(noFallback.isEmpty)
        #expect(plan(nil, ["A": poster], missing: [fallback.path]).isEmpty)
    }

    @Test func nothingOfOursOnScreenMeansNothingToDo() {
        #expect(plan(recorded, ["A": beach, "B": city]).isEmpty)
    }
}

struct OriginalsCodingTests {
    @Test func aRecordSurvivesItsJSON() {
        let recorded = OriginalPictures(screens: [
            "A": beach,
            "B": DesktopPicture(
                path: city.path,
                options: DesktopPictureOptions(scaling: 1, allowsClipping: false, fillColor: [0, 0.5, 1, 1]))
        ])
        #expect(OriginalPictures(json: recorded.json()) == recorded)
    }

    @Test func notJSONIsNoRecord() {
        #expect(OriginalPictures(json: Data("not json".utf8)) == nil)
    }
}

/// Each event reads as the line the app wrote before Desktop published events.
struct DesktopLogLineTests {
    @Test(arguments: [
        (DesktopEvent.originalsRecorded(screens: ["A", "B"]),
         LogLine(cause: "desktop-picture", message: #"recorded originals for screens=["A", "B"]"#)),
        (.originalsNotRecorded(reason: "disk full"),
         LogLine(cause: "desktop-picture", message: "cannot record originals: disk full")),
        (.originalsUnreadable(location: "/support/original-desktop-pictures.json"),
         LogLine(cause: "desktop-picture", message: "cannot read /support/original-desktop-pictures.json")),
        (.posterNotSet(screen: "A", reason: "refused"),
         LogLine(cause: "desktop-picture", message: "cannot set Poster on A: refused")),
        (.restored(screen: "A", picture: beach.path),
         LogLine(cause: "restore", message: "screen=A picture=/Users/me/Pictures/beach.jpg")),
        (.restoreFailed(screen: "A", reason: "refused"),
         LogLine(cause: "restore", message: "screen=A failed: refused")),
        (.nothingToRestore, LogLine(cause: "restore", message: "no screen shows a Poster; nothing to restore"))
    ])
    func readsAsBefore(event: DesktopEvent, line: LogLine) {
        #expect(event.logLine == line)
    }

    @Test func settingThePosterIsNotLogged() {
        #expect(DesktopEvent.posterSet(URL(fileURLWithPath: poster.path), screens: ["A"]).logLine == nil)
    }

    @Test func theSliceStartsEmpty() {
        #expect(DesktopSlice() == DesktopSlice(recordedScreens: [], poster: nil))
    }
}
