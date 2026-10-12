import Playback
import SharedKernel
import Testing

// MARK: - Playback event log lines
// Every Playback event renders the line the player, crossfader, windows and app delegate wrote before it moved here.

private let rain = VideoID("rain.mp4")

@Test(arguments: [
    (PlaybackEvent.recovery(.scheduled(
        cause: .stuck, video: rain, position: 42.46, delay: 60, detail: "player=none")),
     "recovery", "cause=stuck video=rain.mp4 position=42.5 rebuild-in=60s player=none"),
    (.recovery(.scheduled(cause: .fileMissing, video: nil, position: 0, delay: 0, detail: "on folder-change")),
     "recovery", "cause=file-missing video=none position=0.0 rebuild-in=0s on folder-change"),
    (.recovery(.resting(cause: .failed, video: rain, attempts: 3, detail: "item failed player=none")),
     "recovery", "cause=failed video=rain.mp4 resting on Poster after 3 attempts item failed player=none"),
    (.recovery(.restingWithoutVideo(video: nil, detail: "at launch")),
     "recovery", "cause=no-video video=none resting on Poster until a video is added at launch"),
    (.recovery(.built(cause: .launch, video: rain, at: 0)), "launch", "playing video=rain.mp4 at=0.0"),
    (.recovery(.built(cause: .recovery, video: rain, at: 12.34)), "recovery", "rebuilding video=rain.mp4 at=12.3"),
    (.recovery(.built(cause: .power, video: rain, at: 3)), "power", "rebuilding video=rain.mp4 at=3.0"),
    (.recovery(.heldForPower(cause: .launch)), "launch", "Low Power Mode: holding on the Poster"),
    (.recovery(.folderChangeHeldForPower), "folder-change", "Low Power Mode: the Current video loads when it ends")
])
func recoveryLinesReadAsBefore(event: PlaybackEvent, cause: String, message: String) {
    #expect(event.logLine == LogLine(cause: cause, message: message))
}

@Test(arguments: [
    (CrossfadeStep.cut(rain), "cut video=rain.mp4"),
    (.loading(rain), "loading video=rain.mp4"),
    (.fading(rain, duration: 20), "fading video=rain.mp4 over=20s"),
    (.done(rain), "done video=rain.mp4"),
    (.droppedIncoming(nil), "dropped incoming video=none"),
    (.abandoned(rain), "abandoned video=rain.mp4: failed or not ready; keeping the Current video"),
    (.promotedWithoutIncoming(rain), "promote without incoming video=rain.mp4; cutting")
])
func crossfadeLinesReadAsBefore(step: CrossfadeStep, message: String) {
    #expect(PlaybackEvent.crossfade(step).logLine == LogLine(cause: "crossfade", message: message))
}

@Test func playbackStateLinesKeepTheOldModeNames() {
    let event = PlaybackEvent.stateChanged(
        input: .lowPower(true), action: .tearDown, state: .posterOnly, video: rain)
    #expect(event.logLine == LogLine(
        cause: "playback", message: "event=lowPower(true) action=tearDown mode=posterOnly video=rain.mp4"))
    let covered = PlaybackEvent.stateChanged(
        input: .allWindowsOccluded(true), action: .pause, state: .paused, video: nil)
    #expect(covered.logLine?.message == "event=allWindowsOccluded(true) action=pause mode=paused video=none")
    let awake = PlaybackEvent.stateChanged(
        input: .screensAsleep(false), action: .resume, state: .playing, video: rain)
    #expect(awake.logLine?.message == "event=screensAsleep(false) action=resume mode=playing video=rain.mp4")
}

@Test func windowSystemAndDiagnosticLinesReadAsBefore() {
    #expect(PlaybackEvent.occlusionChanged(.windowsBuilt(count: 2), isEveryWindowOccluded: false).logLine
        == LogLine(cause: "occlusion", message: "windows=2 all-occluded=no"))
    #expect(PlaybackEvent.occlusionChanged(.screen(index: 1, isVisible: false), isEveryWindowOccluded: true).logLine
        == LogLine(cause: "occlusion", message: "screen=1 visible=no all-occluded=yes"))
    #expect(PlaybackEvent.screensAsleep.logLine == LogLine(cause: "screens-sleep", message: "pausing shared player"))
    #expect(PlaybackEvent.lowPowerModeChanged(isOn: true).logLine == LogLine(cause: "power", message: "low-power=on"))
    #expect(PlaybackEvent.lowPowerModeChanged(isOn: false).logLine?.message == "low-power=off")
    let report = PlaybackEvent.playerStateReported(cause: "wake", video: rain, report: .noPlayer)
    #expect(report.logLine == LogLine(cause: "wake", message: "video=rain.mp4 player=none"))
    #expect(PlaybackEvent.videoShown(rain).logLine == nil)
}
