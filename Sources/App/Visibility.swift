import AppKit

// MARK: - Visibility
// Whether the Live wallpaper can be seen: Unseen, Veiled or Visible (see CONTEXT.md). A seam for ticket 07, which
// feeds it occlusion, screen sleep and session changes and decides Veiled on demand; until then it stays Visible
// and nothing reads it.

final class Visibility {
    /// Called on the main queue whenever `state` changes.
    var onChange: (VisibilityState) -> Void = { _ in }

    private(set) var state: VisibilityState = .visible
}
