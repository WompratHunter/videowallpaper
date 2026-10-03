import AppKit

// MARK: - Where the app keeps its files
// Everything the app writes lives under Application Support; the Wallpaper folder holds only the user's videos.

enum AppFiles {
    static let wallpaperDirectory = debugFolder
        ?? URL(fileURLWithPath: NSString("~/Movies/LiveWallpaper").expandingTildeInPath)
    /// A debug run on its own folder keeps its cache and Posters beside it, so it can't prune the installed app's.
    static let supportDirectory = debugFolder.map {
        $0.deletingLastPathComponent().appendingPathComponent("\($0.lastPathComponent)-support", isDirectory: true)
    } ?? FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VideoWallpaper", isDirectory: true)
    static let posterDirectory = supportDirectory.appendingPathComponent("posters", isDirectory: true)
    static let analysisCacheFile = supportDirectory.appendingPathComponent("analysis-cache.json")
    static let originalsFile = supportDirectory.appendingPathComponent("original-desktop-pictures.json")
    /// Written into the Wallpaper folder by versions before Posters moved to Application Support.
    static let legacyPoster = wallpaperDirectory.appendingPathComponent(".poster.jpg")
    static let defaultDesktopPicture = URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")

    static let ownPictures = OwnPictures(
        posterDirectory: posterDirectory.resolvingSymlinksInPath().path,
        legacyPoster: legacyPoster.resolvingSymlinksInPath().path)

    /// A manual test's Wallpaper folder, `VIDEOWALLPAPER_FOLDER`, honoured only by a `make debug` build.
    private static var debugFolder: URL? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["VIDEOWALLPAPER_FOLDER"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        #else
        return nil
        #endif
    }
}

// MARK: - Desktop pictures per screen
// NSWorkspace reads and sets the picture of the current Space only; other Spaces keep whatever they had.

enum DesktopPictures {
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
    static func mainScreenPicture() -> URL? {
        NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    }

    /// Sets the Poster on every screen, first recording any original picture not yet recorded.
    static func setPoster(_ poster: URL) {
        recordOriginals()
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(poster, for: screen, options: [:])
            } catch {
                Log.write("desktop-picture", "cannot set Poster on \(key(for: screen)): \(error.localizedDescription)")
            }
        }
    }

    /// Saves the user's own pictures before this app first replaces them; earlier records are never overwritten.
    static func recordOriginals() {
        let existing = loadOriginals()
        // An unreadable record is kept as it is: rewriting it could replace the true originals with our Poster.
        if existing == nil && FileManager.default.fileExists(atPath: AppFiles.originalsFile.path) { return }
        guard let record = originalsToRecord(existing: existing, current: current(), ownPictures: AppFiles.ownPictures)
        else { return }
        do {
            try FileManager.default.createDirectory(at: AppFiles.supportDirectory, withIntermediateDirectories: true)
            try record.json().write(to: AppFiles.originalsFile, options: .atomic)
            Log.write("desktop-picture", "recorded originals for screens=\(record.screens.keys.sorted())")
        } catch {
            Log.write("desktop-picture", "cannot record originals: \(error.localizedDescription)")
        }
    }

    /// The `--restore-wallpaper` command: puts back the original picture on every screen showing our Poster.
    /// Returns the process exit status.
    static func restoreOriginals() -> Int32 {
        let originals = loadOriginals()
        let fallback = DesktopPicture(path: AppFiles.defaultDesktopPicture.path, options: DesktopPictureOptions())
        let plan = restorePlan(
            originals: originals, current: current(), ownPictures: AppFiles.ownPictures, fallback: fallback
        ) {
            FileManager.default.fileExists(atPath: $0)
        }
        var status: Int32 = 0
        for screen in NSScreen.screens {
            guard let picture = plan[key(for: screen)] else { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(
                    URL(fileURLWithPath: picture.path), for: screen, options: workspaceOptions(from: picture.options))
                Log.write("restore", "screen=\(key(for: screen)) picture=\(picture.path)")
            } catch {
                Log.write("restore", "screen=\(key(for: screen)) failed: \(error.localizedDescription)")
                status = 1
            }
        }
        if plan.isEmpty { Log.write("restore", "no screen shows a Poster; nothing to restore") }
        return status
    }

    /// The recorded originals; nil when none were recorded, or (logged) when the record can't be read.
    private static func loadOriginals() -> OriginalPictures? {
        guard let data = try? Data(contentsOf: AppFiles.originalsFile) else { return nil }
        guard let originals = OriginalPictures(json: data) else {
            Log.write("desktop-picture", "cannot read \(AppFiles.originalsFile.path)")
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
