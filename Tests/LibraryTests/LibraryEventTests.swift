import Foundation
import Library
import SharedKernel
import Testing

// MARK: - Library event tests
// Each event's log line reads exactly as the line the app wrote before events existed.

private func video(_ name: String) -> EligibleVideo {
    EligibleVideo(id: VideoID(name), version: Version(size: 1, modifiedMilliseconds: 0), meanLuminance: 0.2)
}

private let rain = VideoID("rain.mp4")

@Test(arguments: [(EligibilityCause.analysis, "analysis"), (.folderChange, "folder-change")])
func eligibleSetChangedLogsItsCount(cause: EligibilityCause, logged: String) {
    let event = LibraryEvent.eligibleSetChanged(eligible: [video("rain.mp4"), video("sea.mp4")], cause: cause)
    #expect(event.logLine == LogLine(cause: logged, message: "eligible videos=2"))
}

@Test(arguments: [
    (LibraryEvent.settled(videos: [rain, VideoID("sea.mp4")]), "folder-change", "settled videos=2"),
    (.analysed(
        rain, version: Version(size: 1, modifiedMilliseconds: 0),
        report: AnalysisReport(meanLuminance: 0.1634, flashesPerSecond: 1, posterSeconds: 7.5, took: 2.34)),
     "analysis", "video=rain.mp4 luminance=0.163 flashes=1.0/s poster=7.50s took=2.3s"),
    (.analysisPaused(rain), "analysis", "video=rain.mp4 paused for Low Power Mode"),
    (.analysisFailed(rain, reason: "noVideoTrack"), "analysis",
     "video=rain.mp4 failed: noVideoTrack; it will not play"),
    (.analysisCacheUnreadable, "analysis", "cache unreadable or from another version; videos will be analysed again"),
    (.analysisCacheNotSaved(reason: "disk full"), "analysis", "cannot save cache: disk full"),
    (.excluded(rain, flashesPerSecond: 6), "flash", "excluded video=rain.mp4 flashes=6.0/s (limit 3/s)"),
    (.overridden(rain, flashesPerSecond: 4.5), "flash",
     "override video=rain.mp4 flashes=4.5/s plays (in FlashOverride)"),
    (.posterNotSaved(fileName: "poster-1.jpg", reason: "disk full"), "poster", "cannot save poster-1.jpg: disk full"),
    (.launchUnderlay(fileName: "poster-1.jpg"), "launch", "no screened video yet; underlay=poster-1.jpg"),
    (.noLaunchUnderlay, "launch", "no Poster or desktop picture to show under the video"),
    (.legacyPosterRemoved, "launch", "removed legacy Poster from the Wallpaper folder"),
    (.legacyPosterNotRemoved(reason: "denied"), "launch", "cannot remove legacy Poster: denied"),
    (.folderNotWatched(path: "/v"), "launch", "cannot watch /v: folder changes will not be seen")
])
func eachEventLogsTodaysLine(event: LibraryEvent, cause: String, message: String) {
    #expect(event.logLine == LogLine(cause: cause, message: message))
}
