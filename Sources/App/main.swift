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
        .filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }
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
    private var tickTimer: Timer?
    private let wallpaperDir = URL(fileURLWithPath: NSString("~/Movies/LiveWallpaper").expandingTildeInPath)

    func applicationDidFinishLaunching(_ n: Notification) {
        Log.write("launch", "pid=\(ProcessInfo.processInfo.processIdentifier) screens=\(NSScreen.screens.count)")
        player.videoProvider = { [weak self] in self.flatMap { newestVideo(in: $0.wallpaperDir) } }
        player.onVideoChange = { [weak self] url in self?.exportPoster(from: url) }
        buildWindows()
        loadVideo()
        startFolderWatch()
        startTickTimer()
        observeSystemEvents()
        player.checkAfterWake(cause: "launch")
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
        guard let url = newestVideo(in: wallpaperDir), url != player.video else { return }
        player.show(url)
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
        src.setEventHandler { [weak self] in
            self?.player.resetBackoff(on: .folderChange)
            self?.loadVideo()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        folderWatch = src
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
        player.checkAfterWake(cause: "screens-wake")
    }

    @objc private func systemWake() {
        player.resetBackoff(on: .wake)
        player.checkAfterWake(cause: "wake")
    }

    @objc private func sessionActive() { player.checkAfterWake(cause: "session-active") }

    @objc private func screenUnlocked() {
        player.resetBackoff(on: .unlock)
        player.checkAfterWake(cause: "unlock")
    }

    @objc private func screensChanged() { buildWindows() }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
