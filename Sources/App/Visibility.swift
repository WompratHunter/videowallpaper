import AppKit

// MARK: - Visibility
// Whether the Live wallpaper can be seen: Unseen, Veiled or Visible (see CONTEXT.md). Unseen follows notifications
// with no polling. Veiled needs the window list, which is read only when a caller asks (`checkVeil`, on each tick
// while a switch is due), so an idle desktop never pays for it. Only window bounds and layers are read, which
// needs no Screen Recording permission.

final class Visibility {
    /// Called on the main queue whenever `state` changes.
    var onChange: (VisibilityState) -> Void = { _ in }

    var state: VisibilityState { tracker.state }
    private var tracker = VisibilityTracker()
    private var veilExpiry: DispatchWorkItem?

    /// Main queue only.
    func apply(_ event: VisibilityEvent, cause: String) {
        report(tracker.apply(event, at: Date()), cause: cause, detail: "\(event)")
    }

    /// Samples window coverage and returns the state that follows. Call it on every tick while a switch is due:
    /// Veiled needs 30 s of continuous samples. Main queue only.
    @discardableResult
    func checkVeil() -> VisibilityState {
        sampleCoverage()
        return state
    }

    /// Returns the coverage sampled, or nil when Unseen made the window list not worth reading.
    @discardableResult
    private func sampleCoverage() -> Double? {
        guard tracker.needsCoverageSample else { return nil }
        let coverage = Self.currentCoverage()
        let change = tracker.sample(coverage: coverage, at: Date())
        report(change, cause: "veil", detail: "coverage=\(Self.percent(coverage))")
        scheduleVeilExpiry()
        return coverage
    }

    /// Once callers stop asking, the last sample stops proving coverage; re-check just after it lapses so a stale
    /// Veiled is reported as the change it is.
    private func scheduleVeilExpiry() {
        veilExpiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.report(self.tracker.refresh(at: Date()), cause: "veil", detail: "no recent coverage sample")
        }
        veilExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + VeilTracker.maxSampleGap + 1, execute: expiry)
    }

    private func report(_ change: VisibilityState?, cause: String, detail: String) {
        guard let change else { return }
        Log.write(cause, "visibility=\(change.rawValue) \(detail)")
        onChange(change)
    }

    // MARK: - Window list

    /// The least-covered screen's coverage by on-screen normal-layer windows. Window-list bounds and display
    /// bounds share the global top-left-origin space, so no flipping is needed.
    private static func currentCoverage() -> Double {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            Log.write("veil", "window list unavailable; counting the desktop as uncovered")
            return 0
        }
        let windows = info.compactMap(listedWindow)
        let screens = NSScreen.screens.compactMap { screen -> ScreenRect? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return rect(CGDisplayBounds(CGDirectDisplayID(id.uint32Value)))
        }
        return leastCoverage(of: windows, screens: screens)
    }

    private static func listedWindow(_ entry: [String: Any]) -> ListedWindow? {
        guard let layer = entry[kCGWindowLayer as String] as? Int,
              let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
        let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
        return ListedWindow(layer: layer, alpha: alpha, bounds: rect(bounds))
    }

    private static func rect(_ cg: CGRect) -> ScreenRect {
        ScreenRect(minX: Double(cg.minX), minY: Double(cg.minY), width: Double(cg.width), height: Double(cg.height))
    }

    private static func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }
}

// MARK: - Veil probe

extension Visibility {
    /// `--check-veil`: samples coverage every 5 s for 45 s and logs each sample, so Veiled can be checked by hand
    /// before anything in the app asks for it. Runs in its own process, never touching the running app.
    static func runVeilProbe() -> Never {
        let probe = Visibility()
        var remaining = 9
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            let coverage = probe.sampleCoverage().map(Self.percent) ?? "n/a"
            Log.write("veil-probe", "coverage=\(coverage) state=\(probe.state.rawValue)")
            remaining -= 1
            if remaining == 0 { exit(0) }
        }
        RunLoop.main.run()
        exit(0)
    }
}
