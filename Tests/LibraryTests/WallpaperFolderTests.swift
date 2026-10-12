import Foundation
@testable import Library
import Testing

// MARK: - Wallpaper folder tests: which files are videos, and the settle check

private func file(_ size: Int64, _ seconds: TimeInterval = 0) -> VideoFile {
    VideoFile(size: size, modified: Date(timeIntervalSince1970: seconds))
}

private func outcome(changed: Bool, again: Bool) -> SettleOutcome {
    SettleOutcome(isReadyChanged: changed, needsAnotherCheck: again)
}

private let launchTime = Date(timeIntervalSince1970: 1000)

@Suite struct WallpaperFolderTests {
    @Test func onlyVisibleVideoFilesAreVideos() {
        #expect(isWallpaperVideo(named: "beach.mp4"), "mp4 is a video")
        #expect(isWallpaperVideo(named: "City.MOV"), "extension match ignores case")
        #expect(isWallpaperVideo(named: "clip.m4v"), "m4v is a video")
        #expect(!isWallpaperVideo(named: ".poster.jpg"), "the Poster export is not a video")
        #expect(!isWallpaperVideo(named: ".DS_Store"), "Finder metadata is not a video")
        #expect(!isWallpaperVideo(named: ".hidden.mp4"), "hidden files are ignored")
        #expect(!isWallpaperVideo(named: "notes.txt"), "other files are ignored")
    }

    @Test func onlyVideosCountAsAChange() {
        let start = Date(timeIntervalSince1970: 0)
        let before = videoListing(of: ["beach.mp4": start])
        #expect(videoListing(of: ["beach.mp4": start, ".poster.jpg": start, ".DS_Store": start]) == before)
        #expect(videoListing(of: ["beach.mp4": start, "city.mov": start]) != before, "a new video is a change")
        #expect(videoListing(of: [:]) != before, "a removed video is a change")
        #expect(videoListing(of: ["beach.mp4": start.addingTimeInterval(1)]) != before, "a replaced video is a change")
    }

    @Test func aVideoSettlesWhenItsSizeHolds() {
        let earlier = ["done.mp4": file(500), "copying.mp4": file(100), "empty.mp4": file(0), "gone.mp4": file(9)]
        let later = ["done.mp4": file(500), "copying.mp4": file(300), "empty.mp4": file(0), "new.mp4": file(50, 7)]
        let settled = settledVideos(earlier: earlier, later: later)
        #expect(Set(settled.keys) == ["done.mp4"])
        #expect(settled["done.mp4"] == Date(timeIntervalSince1970: 0))
    }

    @Test func launchSettlesVideosUntouchedForTheCheckInterval() {
        // Untouched for the check interval: settled at launch, so a normal launch plays without waiting. Written in
        // the last 3 s (still being copied) or empty: not loaded until the first check finds it stable.
        let snapshot = [
            "rain.mp4": file(500, 900), "edge.mp4": file(500, 997), "copying.mp4": file(100, 999),
            "empty.mp4": file(0, 900)
        ]
        var settler = FolderSettler(launch: snapshot, now: launchTime)
        #expect(Set(settler.ready.keys) == ["edge.mp4", "rain.mp4"])
        let scheduled = settler.noteEvent(snapshot)
        #expect(!scheduled, "the launch check is already pending")
        // Finished copying by the first check: loaded then.
        let later = ["rain.mp4": file(500, 900), "edge.mp4": file(500, 997), "copying.mp4": file(100, 999)]
        let first = settler.check(later)
        #expect(first == outcome(changed: true, again: false))
        #expect(Set(settler.ready.keys) == ["copying.mp4", "edge.mp4", "rain.mp4"])
    }

    @Test func theSettlerFollowsCopiesDeletionsAndPlaceholders() {
        // A copy that kept its source's date is trusted at launch, but the first check drops it if it grew.
        var settler = FolderSettler(launch: ["rain.mp4": file(500), "half.mp4": file(100)], now: launchTime)
        #expect(Set(settler.ready.keys) == ["half.mp4", "rain.mp4"])
        var scheduled = settler.noteEvent(["rain.mp4": file(500)])
        #expect(!scheduled, "the launch check is already pending")
        // A copy that was still running at launch is dropped by that first check.
        var checked = settler.check(["rain.mp4": file(500), "half.mp4": file(200)])
        #expect(checked == outcome(changed: true, again: true))
        #expect(Set(settler.ready.keys) == ["rain.mp4"])
        checked = settler.check(["rain.mp4": file(500), "half.mp4": file(200)])
        #expect(checked == outcome(changed: true, again: false))
        #expect(Set(settler.ready.keys) == ["half.mp4", "rain.mp4"])

        // A copy starts: the first event schedules a check; more events while it is pending don't.
        scheduled = settler.noteEvent(["rain.mp4": file(500), "sea.mp4": file(10)])
        #expect(scheduled, "first event schedules a check")
        scheduled = settler.noteEvent(["rain.mp4": file(500), "sea.mp4": file(20)])
        #expect(!scheduled, "pending check is not rescheduled")

        // Still growing 3 s later: not loaded, check again.
        checked = settler.check(["rain.mp4": file(500), "sea.mp4": file(40)])
        #expect(checked == outcome(changed: true, again: true))
        #expect(Set(settler.ready.keys) == ["rain.mp4"])

        // Unchanged across two checks: settled and loadable; nothing left to watch.
        checked = settler.check(["rain.mp4": file(500), "sea.mp4": file(40, 3)])
        #expect(checked == outcome(changed: true, again: false))
        #expect(Set(settler.ready.keys) == ["rain.mp4", "sea.mp4"])
        #expect(settler.ready["sea.mp4"] == Date(timeIntervalSince1970: 3))

        // An event that changes nothing (e.g. the Poster export) does not disturb the player.
        scheduled = settler.noteEvent(["rain.mp4": file(500), "sea.mp4": file(40, 3)])
        #expect(scheduled, "event schedules a check")
        checked = settler.check(["rain.mp4": file(500), "sea.mp4": file(40, 3)])
        #expect(checked == outcome(changed: false, again: false))

        // A deletion drops the file once checked.
        scheduled = settler.noteEvent(["sea.mp4": file(40, 3)])
        #expect(scheduled, "deletion schedules a check")
        checked = settler.check(["sea.mp4": file(40, 3)])
        #expect(checked == outcome(changed: true, again: false))
        #expect(Set(settler.ready.keys) == ["sea.mp4"])

        // An empty placeholder that never grows is neither loaded nor polled forever.
        scheduled = settler.noteEvent(["sea.mp4": file(40, 3)])
        #expect(scheduled, "an event schedules a check")
        checked = settler.check(["sea.mp4": file(40, 3), "stub.mp4": file(0)])
        #expect(checked == outcome(changed: false, again: true))
        checked = settler.check(["sea.mp4": file(40, 3), "stub.mp4": file(0)])
        #expect(checked == outcome(changed: false, again: false))
        #expect(Set(settler.ready.keys) == ["sea.mp4"])
    }
}
