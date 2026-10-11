import Foundation
import Presence
import SharedKernel
import TestSupport
import Testing

// MARK: - Presence service tests
// The service on fake ports: what it reports, and the log lines its events render, which read as they always have.

@MainActor
struct PresenceServiceTests {
    private let clock = FakeClock()
    private let lockSignal = FakeLockSignal()
    private let windowList = FakeWindowList()
    private let presenceClock: FakePresenceClock
    private let service: PresenceService
    private let recorder = Recorder()

    init() {
        presenceClock = FakePresenceClock { [clock] in clock.now }
        service = PresenceService(lockSignal: lockSignal, windowList: windowList, clock: presenceClock)
        service.onEvent = { [recorder] in recorder.events.append($0) }
    }

    @Test func anInputChangeIsReportedOnceWithItsLogLine() {
        service.apply(.locked(true), cause: "lock")
        service.apply(.screensAsleep(true), cause: "screens-sleep")

        #expect(service.state == .unseen)
        #expect(service.slice == PresenceSlice(current: .unseen))
        #expect(recorder.events == [.changed(to: .unseen, because: .input(.locked(true), cause: "lock"))])
        #expect(recorder.lines == [LogLine(cause: "lock", message: "visibility=unseen locked(true)")])
    }

    @Test func lockSignalsGoToTheObserverOnly() {
        var heard: [Bool] = []
        service.observeLock { heard.append($0) }
        #expect(lockSignal.isStarted)

        lockSignal.lock()
        lockSignal.unlock()

        // The coordinator decides what a lock means; the service only hands it on.
        #expect(heard == [true, false])
        #expect(service.state == .visible)
    }

    @Test func coverageHeldForThirtySecondsVeilsThenLapses() {
        windowList.coverEveryScreen()
        for _ in 0...6 {
            service.checkVeil()
            clock.advance(by: 5)
        }
        #expect(service.state == .veiled)
        #expect(recorder.lines == [LogLine(cause: "veil", message: "visibility=veiled coverage=100.0%")])

        // Nobody asks again: 13 s after the last sample, just past the 12 s it counts for, Veiled is reported gone.
        clock.advance(by: 8)
        presenceClock.runDue()
        #expect(service.state == .visible)
        #expect(recorder.lines.last == LogLine(cause: "veil", message: "visibility=visible no recent coverage sample"))
    }

    @Test func theWindowListIsNotReadWhileUnseen() {
        service.apply(.everyWindowOccluded(true), cause: "occlusion")
        #expect(service.checkVeil() == .unseen)
        #expect(windowList.reads == 0)
        #expect(!recorder.events.contains { if case .coverageSampled = $0 { return true } else { return false } })
    }

    @Test func anUnreadableWindowListCountsAsUncovered() {
        windowList.listed = nil
        service.checkVeil()
        #expect(recorder.events == [.windowListUnavailable, .coverageSampled(0)])
        #expect(recorder.lines == [
            LogLine(cause: "veil", message: "window list unavailable; counting the desktop as uncovered")
        ])
    }

    @Test func theVeilProbeLineReadsAsBefore() {
        windowList.coverEveryScreen()
        #expect(service.probeVeil() == LogLine(cause: "veil-probe", message: "coverage=100.0% state=visible"))
        service.apply(.sessionInactive(true), cause: "session-inactive")
        #expect(service.probeVeil() == LogLine(cause: "veil-probe", message: "coverage=n/a state=unseen"))
    }

    @Test(arguments: [
        (PresenceInput.everyWindowOccluded(false), "occlusion", "visibility=visible everyWindowOccluded(false)"),
        (.screensAsleep(true), "screens-sleep", "visibility=unseen screensAsleep(true)"),
        (.sessionInactive(false), "session-active", "visibility=visible sessionInactive(false)"),
        (.locked(false), "unlock", "visibility=visible locked(false)")
    ])
    func everyInputRendersAsBefore(_ input: PresenceInput, cause: String, message: String) {
        let state: SharedKernel.Presence = message.contains("unseen") ? .unseen : .visible
        let event = PresenceEvent.changed(to: state, because: .input(input, cause: cause))
        #expect(event.logLine == LogLine(cause: cause, message: message))
    }

    @Test func coverageRendersToOneDecimal() {
        let event = PresenceEvent.changed(to: .visible, because: .coverage(0.9437))
        #expect(event.logLine == LogLine(cause: "veil", message: "visibility=visible coverage=94.4%"))
        #expect(PresenceEvent.coverageSampled(0.97).logLine == nil)
    }
}

@MainActor
private final class Recorder {
    var events: [PresenceEvent] = []
    var lines: [LogLine] { events.compactMap(\.logLine) }
}
