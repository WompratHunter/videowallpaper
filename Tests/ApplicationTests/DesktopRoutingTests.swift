import Application
import Desktop
import Foundation
import TestSupport
import Testing

// MARK: - Desktop
// The user's own desktop pictures through the coordinator, on an in-memory picture per screen: they are recorded
// before the first Poster replaces them, our own Poster is never recorded as an original, and restoring touches only
// screens showing our Poster, falling back to another screen's original and then the system default.

@MainActor
struct DesktopRoutingTests {
    private let dusk = AppHarness.video("dusk.mp4", 0.16)
    private let beach = "/Users/me/Pictures/beach.jpg"
    private let city = "/Users/me/Pictures/city.heic"
    private let forest = "/Users/me/Pictures/forest.jpg"
    private let poster = URL(fileURLWithPath: FakeDesktop.posterDirectory + "/poster-dusk.jpg")

    /// Launches on `screens` (each screen's picture) and shows the Current video's Poster as the desktop picture.
    private func launch(_ screens: KeyValuePairs<String, String>) throws -> AppHarness {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk]))
        for (screen, path) in screens { app.desktop.pictures.show(path, on: screen) }
        app.coordinator.launch()
        let video = try #require(app.player.video)
        #expect(app.library.deliverPoster(for: video, file: poster) == true)
        return app
    }

    private func desktopEvents(_ app: AppHarness) -> [DesktopEvent] {
        app.events.compactMap { event in
            guard case .desktop(let desktop) = event else { return nil }
            return desktop
        }
    }

    @Test func theFirstPosterRecordsOriginalsFirst() throws {
        let app = AppHarness(library: FakeLibrary(eligible: [dusk]))
        app.desktop.pictures.show(beach, on: "main")
        app.desktop.pictures.show(city, on: "side")
        app.coordinator.launch()

        // Recorded at launch, before anything could change the desktop picture.
        #expect(app.events.first == .desktop(.originalsRecorded(screens: ["main", "side"])))
        #expect(app.desktop.posters.isEmpty)

        // A screen connected since is recorded before the Poster replaces its picture.
        app.desktop.pictures.show(forest, on: "new")
        let video = try #require(app.player.video)
        app.library.deliverPoster(for: video, file: poster)

        #expect(desktopEvents(app).suffix(2) == [
            .originalsRecorded(screens: ["main", "new", "side"]),
            .posterSet(poster, screens: ["main", "side", "new"])
        ])
        #expect(app.desktop.posters == [poster, poster, poster])
        #expect(app.coordinator.snapshot.desktop == DesktopSlice(
            recordedScreens: ["main", "new", "side"], poster: poster))
    }

    @Test func aScreenAlreadyShowingOurPosterIsNotRecorded() throws {
        let app = try launch(["main": FakeDesktop.posterDirectory + "/earlier.jpg", "side": beach])

        #expect(desktopEvents(app) == [
            .originalsRecorded(screens: ["side"]),
            .posterSet(poster, screens: ["main", "side"])
        ])
        #expect(app.coordinator.snapshot.desktop.recordedScreens == ["side"])
    }

    @Test func restoreTouchesOnlyScreensShowingOurPoster() throws {
        let app = try launch(["main": beach, "side": city])
        // The user chose a picture of their own since.
        app.desktop.pictures.show(forest, on: "side")
        let before = app.desktop.posters.count

        #expect(app.desktop.service.restoreOriginals())

        #expect(desktopEvents(app).last == .restored(screen: "main", picture: beach))
        #expect(app.desktop.posters.dropFirst(before) == [URL(fileURLWithPath: beach)])
        #expect(app.desktop.pictures.picture(on: "side")?.path == forest)
        #expect(app.coordinator.snapshot.desktop.poster == nil)
    }

    @Test func restoreFallsBackToAnotherScreensOriginalThenTheDefault() throws {
        let app = try launch(["main": beach, "side": city])
        // A screen connected since shows our Poster too, with no original of its own.
        app.desktop.pictures.show(poster.path, on: "new")

        #expect(app.desktop.service.restoreOriginals())
        // The first original by screen key, so it is stable.
        #expect(app.desktop.pictures.picture(on: "new")?.path == beach)
        #expect(app.desktop.pictures.picture(on: "main")?.path == beach)
        #expect(app.desktop.pictures.picture(on: "side")?.path == city)

        // Every original deleted since: the system default picture.
        app.desktop.pictures.show(poster.path, on: "main")
        app.desktop.pictures.missingFiles = [beach, city]
        #expect(app.desktop.service.restoreOriginals())
        #expect(desktopEvents(app).last == .restored(screen: "main", picture: FakeDesktop.defaultPicture))

        // Not even the default picture: nothing to restore, which is no failure.
        app.desktop.pictures.show(poster.path, on: "main")
        app.desktop.pictures.missingFiles = [beach, city, FakeDesktop.defaultPicture]
        #expect(app.desktop.service.restoreOriginals())
        #expect(desktopEvents(app).last == .nothingToRestore)
    }

    /// `--restore-wallpaper` exits 1 when a screen refuses its picture, after restoring every other screen.
    @Test func aRefusedScreenFailsTheRestore() throws {
        let app = try launch(["main": beach, "side": city])
        app.desktop.pictures.refusing = ["main"]

        #expect(!app.desktop.service.restoreOriginals())

        #expect(desktopEvents(app).suffix(2) == [
            .restoreFailed(screen: "main", reason: "refused"),
            .restored(screen: "side", picture: city)
        ])
    }
}
