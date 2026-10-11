import Foundation

// MARK: - Desktop slice
// Desktop's part of the app snapshot: whose pictures it has recorded and the Poster it last set.

public struct DesktopSlice: Equatable, Sendable {
    /// The screens whose own picture is recorded, sorted.
    public var recordedScreens: [String]
    /// The Poster last set as the desktop picture; nil before the first, and once a screen is restored.
    public var poster: URL?

    public init(recordedScreens: [String] = [], poster: URL? = nil) {
        self.recordedScreens = recordedScreens
        self.poster = poster
    }
}
