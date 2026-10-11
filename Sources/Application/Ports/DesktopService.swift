import Desktop
import Foundation

// MARK: - Desktop service
// Desktop as the coordinator sees it, with today's `DesktopPictures` (Sources/App) as its adapter. A seam for the move
// only: ticket 05 replaces it with the Desktop context's own service, built on a desktop-picture port.

package protocol DesktopService: AnyObject {
    var slice: DesktopSlice { get }

    /// Saves the user's own pictures before this app first replaces them; earlier records are never overwritten.
    func recordOriginals()
    /// Sets the Poster on every screen, first recording any original picture not yet recorded.
    func setPoster(_ poster: URL)
    /// The main screen's current picture, a stand-in underlay while the first Analysis runs.
    func mainScreenPicture() -> URL?
}
