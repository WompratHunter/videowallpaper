// MARK: - Presence
// Whether anyone can see the Live wallpaper (see CONTEXT.md). Presence works it out; Rotation and Playback read it.

public enum Presence: String, Equatable {
    case unseen
    case veiled
    case visible
}
