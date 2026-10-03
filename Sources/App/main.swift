import AppKit
import AVFoundation

// MARK: - Helpers

/// The folder's videos with size and modification date, for the settle check.
func videoSnapshot(of dir: URL) -> [String: VideoFile] {
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
    let items = (try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: Array(keys))) ?? []
    var entries: [String: VideoFile] = [:]
    for item in items {
        let values = try? item.resourceValues(forKeys: keys)
        entries[item.lastPathComponent] = VideoFile(
            size: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate ?? .distantPast)
    }
    return videoListing(of: entries)
}

/// Where a video's Poster is kept: its name changes when the file is replaced, so a stale Poster is never shown.
func posterURL(for video: URL) -> URL? {
    guard let values = try? video.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
          let size = values.fileSize, let modified = values.contentModificationDate
    else { return nil }
    let file = VideoFile(size: Int64(size), modified: modified)
    return AppFiles.posterDirectory.appendingPathComponent(posterFileName(forVideoAt: video.path, file: file))
}

// MARK: - Per-screen wallpaper window
// Only hosts the shared player's layers; all playback lives in Player.

final class WallpaperWindow: NSWindow {
    init(screen: NSScreen, player: Player) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        backgroundColor = .black
        isReleasedWhenClosed = false

        contentView?.wantsLayer = true
        contentView?.layer?.addSublayer(player.makeLayers(frame: CGRect(origin: .zero, size: screen.frame.size)))
    }

    func reassert() {
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        // orderFront only reorders within the desktop level, so the window stays above the system desktop picture
        // (orderBack can sink beneath it) yet below the higher desktop-icon level; it never makes the window key.
        orderFront(nil)
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = Player()
    private var windows: [WallpaperWindow] = []
    private var folderWatch: DispatchSourceFileSystemObject?
    private var settler = FolderSettler(launch: [:], now: Date())
    private var tickTimer: Timer?
    private let wallpaperDir = AppFiles.wallpaperDirectory

    func applicationDidFinishLaunching(_ n: Notification) {
        Log.write("launch", "pid=\(ProcessInfo.processInfo.processIdentifier) screens=\(NSScreen.screens.count)")
        player.videoProvider = { [weak self] in self?.newestSettledVideo() }
        player.onVideoChange = { [weak self] url in self?.showPoster(for: url) }
        // Recorded before anything can change the desktop picture; screens connected later are recorded before the
        // next Poster is set.
        DesktopPictures.recordOriginals()
        removeLegacyPoster()
        // Settled videos are known before the first pick and its saved Poster; Low Power Mode is known before any
        // player is built.
        startFolderWatch()
        loadSavedPoster()
        player.apply(.lowPower(ProcessInfo.processInfo.isLowPowerModeEnabled))
        buildWindows()
        player.start()
        startTickTimer()
        observeSystemEvents()
        player.verifyPlayback(cause: "launch")
    }

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self, selector: #selector(screensSleep),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(screensWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(systemWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(sessionActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        // Unlock has no public NSWorkspace notification; this distributed one is what the system posts.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerStateChanged),
            name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    // MARK: - Window management

    private func buildWindows() {
        // Swapped out before closing: a closing window's occlusion change must not count as the desktop covered.
        let old = windows
        windows = NSScreen.screens.map { WallpaperWindow(screen: $0, player: player) }
        old.forEach { $0.close() }
        // orderFront, not makeKeyAndOrderFront: a desktop window must never take keyboard focus.
        windows.forEach { $0.orderFront(nil) }
        applyOcclusion(change: "windows=\(windows.count)")
    }

    /// Pauses only when every display's window is covered by opaque windows. Translucent ones (e.g. Ghostty)
    /// leave the window's occlusion state visible, so the video keeps playing behind them.
    private func applyOcclusion(change: String) {
        let isAllOccluded = isEveryWindowOccluded(visibility: windows.map { $0.occlusionState.contains(.visible) })
        Log.write("occlusion", "\(change) all-occluded=\(isAllOccluded ? "yes" : "no")")
        player.apply(.allWindowsOccluded(isAllOccluded))
    }

    // MARK: - Shared tick

    private func startTickTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.windows.forEach { $0.reassert() }
            self?.player.healthTick()
        }
        timer.tolerance = 2
        tickTimer = timer
    }

    // MARK: - Notifications

    @objc private func screensSleep() {
        Log.write("screens-sleep", "pausing shared player")
        player.apply(.screensAsleep(true))
    }

    @objc private func screensWake() {
        windows.forEach { $0.reassert() }
        player.resetBackoff(on: .wake)
        player.apply(.screensAsleep(false))
        player.verifyPlayback(cause: "screens-wake")
    }

    @objc private func occlusionChanged(_ note: Notification) {
        guard let window = note.object as? WallpaperWindow, let index = windows.firstIndex(of: window) else { return }
        applyOcclusion(change: "screen=\(index) visible=\(window.occlusionState.contains(.visible) ? "yes" : "no")")
    }

    /// Posted on an arbitrary queue; the player is main-thread only.
    @objc private func powerStateChanged() {
        DispatchQueue.main.async { [weak self] in
            let isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
            Log.write("power", "low-power=\(isOn ? "on" : "off")")
            self?.player.apply(.lowPower(isOn))
        }
    }

    @objc private func systemWake() {
        player.resetBackoff(on: .wake)
        player.verifyPlayback(cause: "wake")
    }

    @objc private func sessionActive() { player.verifyPlayback(cause: "session-active") }

    @objc private func screenUnlocked() {
        player.resetBackoff(on: .unlock)
        player.verifyPlayback(cause: "unlock")
    }

    @objc private func screensChanged() { buildWindows() }
}

// MARK: - Folder watching

extension AppDelegate {
    private func startFolderWatch() {
        try? FileManager.default.createDirectory(at: wallpaperDir, withIntermediateDirectories: true)
        // Seeded before the watch so videos still play if it can't be opened; a copy still running at launch
        // waits for the first check like any other.
        settler = FolderSettler(launch: videoSnapshot(of: wallpaperDir), now: Date())
        scheduleSettleCheck()
        let fd = open(wallpaperDir.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.write("launch", "cannot watch \(wallpaperDir.path): folder changes will not be seen")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main)
        src.setEventHandler { [weak self] in self?.folderChanged() }
        src.setCancelHandler { close(fd) }
        src.resume()
        folderWatch = src
    }

    private func folderChanged() {
        guard settler.noteEvent(videoSnapshot(of: wallpaperDir)) else { return }
        scheduleSettleCheck()
    }

    private func scheduleSettleCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + FolderSettler.checkInterval) { [weak self] in
            self?.settleCheck()
        }
    }

    /// Only settled videos reach the player, so a file still being copied is never loaded.
    private func settleCheck() {
        let outcome = settler.check(videoSnapshot(of: wallpaperDir))
        if outcome.needsAnotherCheck { scheduleSettleCheck() }
        guard outcome.isReadyChanged else { return }
        Log.write("folder-change", "settled videos=\(settler.ready.count)")
        // A renamed or deleted Current video goes through Recovery (logged, Poster during the gap), because
        // AVFoundation may otherwise keep playing the old open file.
        player.folderChanged(newest: newestSettledVideo())
    }

    /// Existence is re-checked so a rebuild in the gap before the next settle check skips a just-deleted file.
    private func newestSettledVideo() -> URL? {
        let present = settler.ready.filter {
            FileManager.default.fileExists(atPath: wallpaperDir.appendingPathComponent($0.key).path)
        }
        return newestVideo(in: present).map { wallpaperDir.appendingPathComponent($0) }
    }
}

// MARK: - Posters for the window underlay, Mission Control and the Lock screen

extension AppDelegate {
    /// The Current video's saved Poster, so the underlay isn't empty while the player starts.
    private func loadSavedPoster() {
        guard let video = newestSettledVideo(), let poster = posterURL(for: video), let image = loadImage(poster)
        else { return }
        player.setPoster(image)
    }

    /// Earlier versions wrote the Poster into the Wallpaper folder; it now lives in Application Support.
    private func removeLegacyPoster() {
        guard FileManager.default.fileExists(atPath: AppFiles.legacyPoster.path) else { return }
        do {
            try FileManager.default.removeItem(at: AppFiles.legacyPoster)
            Log.write("launch", "removed legacy Poster from the Wallpaper folder")
        } catch {
            Log.write("launch", "cannot remove legacy Poster: \(error.localizedDescription)")
        }
    }

    private func loadImage(_ url: URL) -> CGImage? {
        NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Reuses the video's saved Poster, or exports one, then makes it the desktop picture on every screen.
    private func showPoster(for video: URL) {
        guard let poster = posterURL(for: video) else { return }
        guard let image = loadImage(poster) else {
            exportPoster(from: video, to: poster)
            return
        }
        player.setPoster(image)
        DesktopPictures.setPoster(poster)
    }

    private func exportPoster(from video: URL, to poster: URL) {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 3840, height: 2160)
        gen.generateCGImageAsynchronously(for: CMTime(seconds: 5, preferredTimescale: 600)) { img, _, err in
            guard let img, err == nil else { return }
            let isSaved = Self.save(img, to: poster)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.player.video == video else { return }
                self.player.setPoster(img)
                guard isSaved else { return }
                DesktopPictures.setPoster(poster)
                self.pruneStalePosters()
            }
        }
    }

    private static func save(_ image: CGImage, to poster: URL) -> Bool {
        let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        do {
            guard let data else { throw CocoaError(.fileWriteUnknown) }
            try FileManager.default.createDirectory(at: AppFiles.posterDirectory, withIntermediateDirectories: true)
            try data.write(to: poster, options: .atomic)
            return true
        } catch {
            Log.write("poster", "cannot save \(poster.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    /// Posters of videos no longer in the folder are deleted, so Application Support doesn't grow forever.
    private func pruneStalePosters() {
        // Named by posterURL(for:), like the Poster just saved, so a fresh Poster is never pruned.
        let keep = Set(videoSnapshot(of: wallpaperDir).keys.compactMap {
            posterURL(for: wallpaperDir.appendingPathComponent($0))?.lastPathComponent
        })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: AppFiles.posterDirectory.path)) ?? []
        for name in stalePosters(in: names, keeping: keep) {
            try? FileManager.default.removeItem(at: AppFiles.posterDirectory.appendingPathComponent(name))
        }
    }
}

// MARK: - Entry point

let app = NSApplication.shared
// Run by `make uninstall` after the LaunchAgent is unloaded: restore and exit, with no windows or player.
if CommandLine.arguments.contains("--restore-wallpaper") {
    exit(DesktopPictures.restoreOriginals())
}
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
