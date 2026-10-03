import AppKit

// MARK: - Visibility
// Whether the Live wallpaper can be seen: Unseen, Veiled or Visible (see CONTEXT.md). Unseen follows notifications
// with no polling. Veiled needs the window list, which is read only when a caller asks (`checkVeil`, on each tick
// while a switch is due), so an idle desktop never pays for it. Only window bounds and layers are read, which
// needs no Screen Recording permission.

final class Visibility {
    /// Called on the main queue whenever `state` changes.
    var onChange: (VisibilityState) -> Void = { _ in }

    private(set) var state: VisibilityState = .visible
    private var inputs = VisibilityInputs()
    private var veil = VeilTracker()

    /// Main queue only. The coverage clock is re-read so a stale sample can't keep the state Veiled.
    func apply(_ event: VisibilityEvent, cause: String) {
        inputs.apply(event)
        inputs.coveredFor = veil.coveredFor(at: Date())
        update(cause: cause, detail: "\(event)")
    }

    /// Samples window coverage and returns the state that follows. Call it on every tick while a switch is due:
    /// Veiled needs 30 s of continuous samples. Skips the window list while Unseen, which Veiled can't override.
    @discardableResult
    func checkVeil() -> VisibilityState {
        guard classifyVisibility(inputs) != .unseen else { return state }
        let now = Date()
        let coverage = Self.currentCoverage()
        veil.sample(coverage: coverage, at: now)
        inputs.coveredFor = veil.coveredFor(at: now)
        update(cause: "veil", detail: "coverage=\(Self.percent(coverage))")
        return state
    }

    private func update(cause: String, detail: String) {
        let next = classifyVisibility(inputs)
        guard next != state else { return }
        Log.write(cause, "visibility=\(next.rawValue) was=\(state.rawValue) \(detail)")
        state = next
        onChange(next)
    }

    // MARK: - Window list

    /// The least-covered screen's coverage by on-screen normal-layer windows. Window-list bounds and display
    /// bounds share the global top-left-origin space, so no flipping is needed.
    private static func currentCoverage() -> Double {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = info.compactMap(listedWindow)
        let screens = NSScreen.screens.compactMap { screen -> Rect? in
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

    private static func rect(_ cg: CGRect) -> Rect {
        Rect(minX: Double(cg.minX), minY: Double(cg.minY), width: Double(cg.width), height: Double(cg.height))
    }

    private static func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }
}

// MARK: - Veil probe

extension Visibility {
    /// `--check-veil`: samples coverage every 5 s for 45 s and logs each sample, so Veiled can be checked
    /// by hand before anything in the app asks for it. Runs in its own process, never touching the running app.
    static func runVeilProbe() -> Never {
        let probe = Visibility()
        var remaining = 9
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            let state = probe.checkVeil()
            Log.write("veil-probe", "coverage=\(percent(currentCoverage())) state=\(state.rawValue)")
            remaining -= 1
            if remaining == 0 { exit(0) }
        }
        RunLoop.main.run()
        exit(0)
    }
}
