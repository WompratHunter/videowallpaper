import Foundation

// MARK: - Desktop service
// The Desktop context's commands: record the user's own desktop pictures, set the Poster as the desktop picture, and
// restore the originals (`--restore-wallpaper`). What it does is published as `DesktopEvent`s through `onEvent`.

@MainActor
public final class DesktopService {
    /// Set by whoever runs Desktop: the coordinator, or the log sink for `--restore-wallpaper`.
    public var onEvent: (DesktopEvent) -> Void = { _ in }
    public private(set) var slice = DesktopSlice()

    private let pictures: DesktopPicturePort
    private let originals: OriginalsStore
    /// The app's own Posters, never recorded as an original.
    private let ownPictures: OwnPictures
    /// Restored when a screen has no recorded original.
    private let defaultPicture: URL

    public init(
        pictures: DesktopPicturePort, originals: OriginalsStore, ownPictures: OwnPictures, defaultPicture: URL
    ) {
        self.pictures = pictures
        self.originals = originals
        self.ownPictures = ownPictures
        self.defaultPicture = defaultPicture
    }

    /// The main screen's current picture, a stand-in underlay while the first Analysis runs.
    public func mainScreenPicture() -> URL? {
        pictures.mainScreenPicture
    }

    /// Sets the Poster on every screen, first recording any original picture not yet recorded.
    public func setPoster(_ poster: URL) {
        recordOriginals()
        var set: [String] = []
        for screen in pictures.screens {
            do {
                try pictures.setPicture(poster, options: DesktopPictureOptions(), on: screen)
                set.append(screen)
            } catch {
                onEvent(.posterNotSet(screen: screen, reason: error.localizedDescription))
            }
        }
        guard !set.isEmpty else { return }
        slice.poster = poster
        onEvent(.posterSet(poster, screens: set))
    }

    /// Saves the user's own pictures before this app first replaces them; earlier records are never overwritten.
    public func recordOriginals() {
        let existing = loadOriginals()
        // An unreadable record is kept as it is: rewriting it could replace the true originals with our Poster.
        if existing == nil && originals.exists { return }
        if let existing { slice.recordedScreens = existing.screens.keys.sorted() }
        guard let record = originalsToRecord(existing: existing, current: currentPictures(), ownPictures: ownPictures)
        else { return }
        do {
            try originals.write(record.json())
            slice.recordedScreens = record.screens.keys.sorted()
            onEvent(.originalsRecorded(screens: slice.recordedScreens))
        } catch {
            onEvent(.originalsNotRecorded(reason: error.localizedDescription))
        }
    }

    /// Puts back the original picture on every screen showing our Poster. True unless a screen refused its picture.
    @discardableResult
    public func restoreOriginals() -> Bool {
        let recorded = loadOriginals()
        let fallback = DesktopPicture(path: defaultPicture.path, options: DesktopPictureOptions())
        let plan = restorePlan(
            originals: recorded, current: currentPictures(), ownPictures: ownPictures, fallback: fallback
        ) { [pictures] in
            pictures.fileExists(atPath: $0)
        }
        var isComplete = true
        for screen in pictures.screens {
            guard let picture = plan[screen] else { continue }
            do {
                try pictures.setPicture(URL(fileURLWithPath: picture.path), options: picture.options, on: screen)
                slice.poster = nil
                onEvent(.restored(screen: screen, picture: picture.path))
            } catch {
                onEvent(.restoreFailed(screen: screen, reason: error.localizedDescription))
                isComplete = false
            }
        }
        if plan.isEmpty { onEvent(.nothingToRestore) }
        return isComplete
    }

    /// The current picture of every connected screen that has one, keyed by screen.
    private func currentPictures() -> [String: DesktopPicture] {
        var current: [String: DesktopPicture] = [:]
        for screen in pictures.screens {
            current[screen] = pictures.picture(on: screen)
        }
        return current
    }

    /// The recorded originals; nil when none were recorded, or (reported) when the record can't be decoded.
    private func loadOriginals() -> OriginalPictures? {
        guard let data = originals.read() else { return nil }
        guard let record = OriginalPictures(json: data) else {
            onEvent(.originalsUnreadable(location: originals.location))
            return nil
        }
        return record
    }
}
