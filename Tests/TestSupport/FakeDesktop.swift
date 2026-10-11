import Application
import Desktop
import Foundation

// MARK: - Fake Desktop
// Stands in for the Desktop service until ticket 05 replaces it with an in-memory per-screen desktop-picture fake.

package final class FakeDesktop: DesktopService {
    package private(set) var recordings = 0
    package private(set) var posters: [URL] = []

    package init() {}

    package var slice: DesktopSlice { DesktopSlice() }

    package func recordOriginals() {
        recordings += 1
    }

    package func setPoster(_ poster: URL) {
        posters.append(poster)
    }

    package func mainScreenPicture() -> URL? { nil }
}
