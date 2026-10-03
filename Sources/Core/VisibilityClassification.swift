import Foundation

// MARK: - Visibility classification
// Whether anyone can see the Live wallpaper (see CONTEXT.md). Ticket 07 adds the full classification, coverage
// computation and the transition each state allows; until then only the all-occluded check drives playback.

enum VisibilityState: String, Equatable {
    case unseen
    case veiled
    case visible
}

/// Each window's "visible" occlusion flag. Translucent windows (e.g. Ghostty) don't clear the flag, so only
/// opaque coverage of every display counts. No windows at all is not "covered".
func isEveryWindowOccluded(visibility: [Bool]) -> Bool {
    !visibility.isEmpty && !visibility.contains(true)
}
