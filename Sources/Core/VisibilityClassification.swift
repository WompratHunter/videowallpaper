import Foundation

// MARK: - Visibility classification
// Whether anyone can see the Live wallpaper (see CONTEXT.md). So far only the all-occluded check exists, and it
// drives playback directly.

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
