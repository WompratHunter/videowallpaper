// MARK: - Occlusion
// When the windows count as covered. Playback owns the windows, so it decides; the coordinator forwards the result to
// the Playback gate and to Presence.

/// Each window's "visible" occlusion flag. Translucent windows (e.g. Ghostty) don't clear the flag, so only
/// opaque coverage of every display counts. No windows at all is not "covered".
func isEveryWindowOccluded(visibility: [Bool]) -> Bool {
    !visibility.isEmpty && !visibility.contains(true)
}
