import Library
import SharedKernel
import Testing

// MARK: - Library event tests
// Each event's log line reads exactly as the line the app wrote before events existed.

private func video(_ name: String) -> EligibleVideo {
    EligibleVideo(id: VideoID(name), version: Version(size: 1, modifiedMilliseconds: 0), meanLuminance: 0.2)
}

@Test(arguments: [(EligibilityCause.analysis, "analysis"), (.folderChange, "folder-change")])
func eligibleSetChangedLogsItsCount(cause: EligibilityCause, logged: String) {
    let event = LibraryEvent.eligibleSetChanged(eligible: [video("rain.mp4"), video("sea.mp4")], cause: cause)
    #expect(event.logLine == LogLine(cause: logged, message: "eligible videos=2"))
}
