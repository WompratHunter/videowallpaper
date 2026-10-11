// MARK: - Occlusion
// Playback's: whether every wallpaper window is hidden, which the windows publish as an input the coordinator forwards
// to the Playback gate and to Presence. Left here, out of the Presence move (ticket 03), for `WallpaperWindows` until
// ticket 07 moves both into Playback.

/// Each window's "visible" occlusion flag. Translucent windows (e.g. Ghostty) don't clear the flag, so only
/// opaque coverage of every display counts. No windows at all is not "covered".
package func isEveryWindowOccluded(visibility: [Bool]) -> Bool {
    !visibility.isEmpty && !visibility.contains(true)
}
