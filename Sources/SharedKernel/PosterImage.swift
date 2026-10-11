import CoreGraphics
import Foundation

// MARK: - Poster image
// Library makes Posters and Playback shows them, so both must agree on what one is. The decoded still is a CGImage
// (CoreGraphics, not AppKit); nothing but the adapters that make and draw it looks inside.

/// A Version's Poster, with its saved file when there is one (the file is what becomes the desktop picture).
public struct PosterImage {
    public let image: CGImage
    public let file: URL?

    public init(image: CGImage, file: URL?) {
        self.image = image
        self.file = file
    }
}
