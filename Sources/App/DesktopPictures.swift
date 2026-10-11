import AppKit
import Application
import Core
import Desktop

// MARK: - Desktop pictures per screen
// NSWorkspace reads and sets the picture of the current Space only; other Spaces keep whatever they had.

package final class DesktopPictures {
    /// Where the user's own pictures are recorded, in Application Support.
    private let originalsFile: URL
    /// The app's own Posters, never recorded as an original.
    private let ownPictures: OwnPictures
    /// Restored when a screen has no recorded original.
    private let defaultPicture: URL

    package init(originalsFile: URL, ownPictures: OwnPictures, defaultPicture: URL) {
        self.originalsFile = originalsFile
        self.ownPictures = ownPictures
        self.defaultPicture = defaultPicture
    }

    /// The current picture of every connected screen, keyed by a stable screen identifier.
    private static func current() -> [String: DesktopPicture] {
        var pictures: [String: DesktopPicture] = [:]
        for screen in NSScreen.screens {
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { continue }
            // Resolved like the app's own paths, so a symlinked home still matches its Posters.
            let raw = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            pictures[key(for: screen)] = DesktopPicture(
                path: url.resolvingSymlinksInPath().path, options: options(from: raw))
        }
        return pictures
    }

    /// The main screen's current picture, a stand-in underlay while the first Analysis runs.
    package func mainScreenPicture() -> URL? {
        NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    }

    /// Sets the Poster on every screen, first recording any original picture not yet recorded.
    package func setPoster(_ poster: URL) {
        recordOriginals()
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(poster, for: screen, options: [:])
            } catch {
                Log.write(
                    "desktop-picture", "cannot set Poster on \(Self.key(for: screen)): \(error.localizedDescription)")
            }
        }
    }

    /// Saves the user's own pictures before this app first replaces them; earlier records are never overwritten.
    package func recordOriginals() {
        let existing = loadOriginals()
        // An unreadable record is kept as it is: rewriting it could replace the true originals with our Poster.
        if existing == nil && FileManager.default.fileExists(atPath: originalsFile.path) { return }
        guard let record = originalsToRecord(existing: existing, current: Self.current(), ownPictures: ownPictures)
        else { return }
        do {
            try FileManager.default.createDirectory(
                at: originalsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try record.json().write(to: originalsFile, options: .atomic)
            Log.write("desktop-picture", "recorded originals for screens=\(record.screens.keys.sorted())")
        } catch {
            Log.write("desktop-picture", "cannot record originals: \(error.localizedDescription)")
        }
    }

    /// The `--restore-wallpaper` command: puts back the original picture on every screen showing our Poster.
    /// Returns the process exit status.
    package func restoreOriginals() -> Int32 {
        let originals = loadOriginals()
        let fallback = DesktopPicture(path: defaultPicture.path, options: DesktopPictureOptions())
        let plan = restorePlan(
            originals: originals, current: Self.current(), ownPictures: ownPictures, fallback: fallback
        ) {
            FileManager.default.fileExists(atPath: $0)
        }
        var status: Int32 = 0
        for screen in NSScreen.screens {
            guard let picture = plan[Self.key(for: screen)] else { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(
                    URL(fileURLWithPath: picture.path), for: screen,
                    options: Self.workspaceOptions(from: picture.options))
                Log.write("restore", "screen=\(Self.key(for: screen)) picture=\(picture.path)")
            } catch {
                Log.write("restore", "screen=\(Self.key(for: screen)) failed: \(error.localizedDescription)")
                status = 1
            }
        }
        if plan.isEmpty { Log.write("restore", "no screen shows a Poster; nothing to restore") }
        return status
    }

    /// The recorded originals; nil when none were recorded, or (logged) when the record can't be read.
    private func loadOriginals() -> OriginalPictures? {
        guard let data = try? Data(contentsOf: originalsFile) else { return nil }
        guard let originals = OriginalPictures(json: data) else {
            Log.write("desktop-picture", "cannot read \(originalsFile.path)")
            return nil
        }
        return originals
    }

    /// The display's UUID survives reboots and reconnection, unlike the numeric display ID.
    private static func key(for screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let displayID = CGDirectDisplayID(number?.uint32Value ?? 0)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid)
        else { return "display-\(displayID)" }
        return text as String
    }

    // MARK: - Option conversion

    private static func options(from raw: [NSWorkspace.DesktopImageOptionKey: Any]) -> DesktopPictureOptions {
        let color = (raw[.fillColor] as? NSColor)?.usingColorSpace(.sRGB)
        return DesktopPictureOptions(
            scaling: (raw[.imageScaling] as? NSNumber)?.uintValue,
            allowsClipping: (raw[.allowClipping] as? NSNumber)?.boolValue,
            fillColor: color.map {
                [$0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent].map(Double.init)
            })
    }

    private static func workspaceOptions(
        from options: DesktopPictureOptions
    ) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        var raw: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling = options.scaling { raw[.imageScaling] = NSNumber(value: scaling) }
        if let clipping = options.allowsClipping { raw[.allowClipping] = NSNumber(value: clipping) }
        if let rgba = options.fillColor, rgba.count == 4 {
            raw[.fillColor] = NSColor(
                srgbRed: CGFloat(rgba[0]), green: CGFloat(rgba[1]), blue: CGFloat(rgba[2]), alpha: CGFloat(rgba[3]))
        }
        return raw
    }
}

extension DesktopPictures: DesktopService {
    package var slice: DesktopSlice { DesktopSlice() }
}
