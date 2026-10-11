import Desktop
import Foundation

// MARK: - Fake Desktop
// The real Desktop service on in-memory fakes of its ports: a desktop picture per screen and the originals record.
// Tests connect screens, change their pictures as the user would, and read back every picture set.

package final class FakeDesktop {
    package static let posterDirectory = "/fake/posters"
    package static let legacyPoster = "/fake/LiveWallpaper/.poster.jpg"
    package static let defaultPicture = "/fake/System/DefaultDesktop.heic"

    package let pictures: FakeDesktopPictures
    package let originals = FakeOriginalsStore()
    package let service: DesktopService

    /// `screens`: each screen's picture path, in the system's order. By default one screen shows an earlier Poster, as
    /// on every launch after the first.
    package init(screens: KeyValuePairs<String, String> = ["main": "\(posterDirectory)/earlier.jpg"]) {
        pictures = FakeDesktopPictures(screens: screens)
        service = DesktopService(
            pictures: pictures,
            originals: originals,
            ownPictures: OwnPictures(posterDirectory: Self.posterDirectory, legacyPoster: Self.legacyPoster),
            defaultPicture: URL(fileURLWithPath: Self.defaultPicture))
    }

    /// Every picture set on a screen, in order.
    package var posters: [URL] { pictures.sets.map { URL(fileURLWithPath: $0.picture.path) } }
}

/// The desktop picture per screen, in memory.
package final class FakeDesktopPictures: DesktopPicturePort {
    package struct Refused: LocalizedError {
        package var errorDescription: String? { "refused" }
    }

    package private(set) var screens: [String] = []
    package private(set) var current: [String: DesktopPicture] = [:]
    /// Screens whose picture the system refuses to set.
    package var refusing: Set<String> = []
    /// Picture files that no longer exist.
    package var missingFiles: Set<String> = []
    package private(set) var sets: [(screen: String, picture: DesktopPicture)] = []

    init(screens: KeyValuePairs<String, String>) {
        for (screen, path) in screens { show(path, on: screen) }
    }

    /// The user (or a newly connected screen) shows `path` on `screen`.
    package func show(_ path: String, on screen: String, options: DesktopPictureOptions = DesktopPictureOptions()) {
        if !screens.contains(screen) { screens.append(screen) }
        current[screen] = DesktopPicture(path: path, options: options)
    }

    package var mainScreenPicture: URL? {
        screens.first.flatMap { current[$0] }.map { URL(fileURLWithPath: $0.path) }
    }

    package func picture(on screen: String) -> DesktopPicture? {
        current[screen]
    }

    package func setPicture(_ file: URL, options: DesktopPictureOptions, on screen: String) throws {
        if refusing.contains(screen) { throw Refused() }
        let picture = DesktopPicture(path: file.path, options: options)
        current[screen] = picture
        sets.append((screen, picture))
    }

    package func fileExists(atPath path: String) -> Bool {
        !missingFiles.contains(path)
    }
}

/// The originals record, in memory.
package final class FakeOriginalsStore: OriginalsStore {
    package var data: Data?
    package var refusesWrites = false

    package let location = "/fake/support/original-desktop-pictures.json"

    package var exists: Bool { data != nil }

    package func read() -> Data? { data }

    package func write(_ data: Data) throws {
        if refusesWrites { throw FakeDesktopPictures.Refused() }
        self.data = data
    }
}
