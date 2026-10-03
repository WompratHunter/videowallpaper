import AppKit
import AVFoundation

// MARK: - Helpers

func newestVideo(in dir: URL) -> URL? {
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles])
    else { return nil }
    return items
        .filter { isWallpaperVideo(named: $0.lastPathComponent) }
        .max {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return a < b
        }
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
        orderFront(nil)
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = Player()
    private var windows: [WallpaperWindow] = []
    private var folderWatch: DispatchSourceFileSystemObject?
    private var videoFiles: [String: Date] = [:]
    private var tickTimer: Timer?
    private let wallpaperDir = URL(fileURLWithPath: NSString("~/Movies/LiveWallpaper").expandingTildeInPath)

    func applicationDidFinishLaunching(_ n: Notification) {
        Log.write("launch", "pid=\(ProcessInfo.processInfo.processIdentifier) screens=\(NSScreen.screens.count)")
        player.videoProvider = { [weak self] in self.flatMap { newestVideo(in: $0.wallpaperDir) } }
        player.onVideoChange = { [weak self] url in self?.exportPoster(from: url) }
        loadSavedPoster()
        buildWindows()
        loadVideo()
        startFolderWatch()
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
    }

    // MARK: - Window management

    private func buildWindows() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { WallpaperWindow(screen: $0, player: player) }
        // orderFront, not makeKeyAndOrderFront: a desktop window must never take keyboard focus.
        windows.forEach { $0.orderFront(nil) }
    }

    private func loadVideo() {
        // A renamed or deleted Current video goes through Recovery (logged, Poster during the gap), which then
        // picks the newest remaining video; AVFoundation may otherwise keep playing the old open file.
        if let current = player.video, !FileManager.default.fileExists(atPath: current.path) {
            player.recover(cause: .fileMissing, detail: "on folder-change")
            return
        }
        guard let url = newestVideo(in: wallpaperDir), url != player.video else { return }
        player.show(url)
    }

    /// The last exported Poster, so the underlay isn't empty while the new one is generated at launch.
    private func loadSavedPoster() {
        let url = wallpaperDir.appendingPathComponent(".poster.jpg")
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        player.setPoster(image)
    }

    // MARK: - Folder watching

    private func startFolderWatch() {
        try? FileManager.default.createDirectory(at: wallpaperDir, withIntermediateDirectories: true)
        let fd = open(wallpaperDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main)
        videoFiles = currentVideoListing()
        src.setEventHandler { [weak self] in self?.folderChanged() }
        src.setCancelHandler { close(fd) }
        src.resume()
        folderWatch = src
    }

    private func folderChanged() {
        let listing = currentVideoListing()
        guard listing != videoFiles else { return }
        videoFiles = listing
        player.resetBackoff(on: .folderChange)
        loadVideo()
    }

    private func currentVideoListing() -> [String: Date] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: wallpaperDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var entries: [String: Date] = [:]
        for item in items {
            entries[item.lastPathComponent] = (try? item.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
        }
        return videoListing(of: entries)
    }

    // MARK: - Poster for the window underlay, Mission Control and the Lock screen

    private func exportPoster(from video: URL) {
        let poster = wallpaperDir.appendingPathComponent(".poster.jpg")
        let asset = AVURLAsset(url: video)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 3840, height: 2160)
        gen.generateCGImageAsynchronously(for: CMTime(seconds: 5, preferredTimescale: 600)) { img, _, err in
            guard let img, err == nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard self?.player.video == video else { return }
                self?.player.setPoster(img)
            }
            let rep = NSBitmapImageRep(cgImage: img)
            if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                try? data.write(to: poster)
                DispatchQueue.main.async(execute: DispatchWorkItem {
                    for screen in NSScreen.screens {
                        try? NSWorkspace.shared.setDesktopImageURL(
                            poster, for: screen, options: [:])
                    }
                })
            }
        }
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
        player.pause()
    }

    @objc private func screensWake() {
        windows.forEach { $0.reassert() }
        player.resetBackoff(on: .wake)
        player.resume()
        player.verifyPlayback(cause: "screens-wake")
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

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
