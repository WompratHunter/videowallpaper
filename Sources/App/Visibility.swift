import Foundation

// MARK: - Visibility
// Whether the Live wallpaper can be seen: Unseen, Veiled or Visible (see CONTEXT.md). Not yet fed any inputs, so it
// stays Visible and nothing reads it; occlusion, screen sleep and session changes will drive it.

final class Visibility {
    /// Called on the main queue whenever `state` changes.
    var onChange: (VisibilityState) -> Void = { _ in }

    private(set) var state: VisibilityState = .visible
}
