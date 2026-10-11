import Foundation

// MARK: - Desktop routes
// When the user's own desktop pictures are recorded and when the Poster becomes the desktop picture; Desktop's events
// go to the event stream.

extension Coordinator {
    /// Recorded before anything can change the desktop picture; screens connected later are recorded before the
    /// next Poster is set.
    func launchDesktop() {
        desktop.onEvent = { [weak self] event in self?.emit(.desktop(event)) }
        desktop.recordOriginals()
    }

    // MARK: - Desktop commands

    func desktopSetPoster(_ file: URL) {
        desktop.setPoster(file)
    }

    func desktopMainScreenPicture() -> URL? {
        desktop.mainScreenPicture()
    }
}
