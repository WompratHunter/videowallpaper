import Foundation
import Library
import SharedKernel

// MARK: - Library routes
// What the Library hears (settings, Low Power Mode) and where its events go. A changed eligible set reaches the
// Rotation before Playback, so Playback is handed the Rotation's new decision; the Library's other events are only
// reported.

extension Coordinator {
    func connectLibrary() {
        library.flashOverrides = { [settings] in settings.load().flashOverrides }
        library.onEvent = { [weak self] event in self?.handle(event) }
    }

    func launchLibrary() {
        library.isLowPowerMode = isLowPowerMode
        library.start()
    }

    private func handle(_ event: LibraryEvent) {
        emit(.library(event))
        guard case .eligibleSetChanged = event else { return }
        // A renamed or deleted Current video goes through Recovery (logged, Poster during the gap), because
        // AVFoundation may otherwise keep playing the old open file. A new video only joins the Rotation here.
        let fade = rotationFolderChanged()
        playbackFolderChanged(fade: fade)
    }

    // MARK: - Library commands

    var eligibleVideos: [EligibleVideo] { library.eligibleVideos }

    var libraryVideoNames: Set<String> { library.videoNames }

    func libraryLowPowerModeChanged(_ isOn: Bool) {
        library.isLowPowerMode = isOn
    }

    func libraryLaunchUnderlay(toPlay video: URL?, desktopPicture: URL?) -> PosterImage? {
        library.launchUnderlay(toPlay: video, desktopPicture: desktopPicture)
    }

    func libraryPoster(for video: URL, use: @escaping (PosterImage) -> Bool) {
        library.poster(for: video, use: use)
    }
}
