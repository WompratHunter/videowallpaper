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

final class WallpaperWindow: NSWindow {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    init(screen: NSScreen) {
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

        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = CGRect(origin: .zero, size: screen.frame.size)
        contentView?.wantsLayer = true
        contentView?.layer?.addSublayer(playerLayer)
    }

    func play(url: URL) {
        looper = nil
        player?.pause()

        let item = AVPlayerItem(url: url)
        let q = AVQueuePlayer(playerItem: item)
        q.isMuted = true
        q.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: q, templateItem: item)
        playerLayer.player = q
        player = q
        q.play()
    }

    func pause() { player?.pause() }
    func resume() { player?.play() }

    func reassert() {
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        orderBack(nil)
        if player?.timeControlStatus == .paused { player?.play() }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [WallpaperWindow] = []
    private var currentVideo: URL?
    private var folderWatch: DispatchSourceFileSystemObject?
    private var reassertTimer: Timer?
    private let wallpaperDir = URL(fileURLWithPath: NSString("~/Movies/LiveWallpaper").expandingTildeInPath)

    func applicationDidFinishLaunching(_ n: Notification) {
        buildWindows()
        startFolderWatch()
        startReassertTimer()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensSleep),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: - Window management

    private func buildWindows() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { WallpaperWindow(screen: $0) }
        windows.forEach { $0.makeKeyAndOrderFront(nil) }
        loadVideo()
    }

    private func loadVideo() {
        guard let url = newestVideo(in: wallpaperDir), url != currentVideo else { return }
        currentVideo = url
        windows.forEach { $0.play(url: url) }
        exportPoster(from: url)
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
        src.setEventHandler { [weak self] in self?.loadVideo() }
        src.setCancelHandler { close(fd) }
        src.resume()
        folderWatch = src
    }

    // MARK: - Static poster for Mission Control / login screen

    private func exportPoster(from video: URL) {
        let poster = wallpaperDir.appendingPathComponent(".poster.jpg")
        let asset = AVURLAsset(url: video)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 3840, height: 2160)
        gen.generateCGImageAsynchronously(for: CMTime(seconds: 5, preferredTimescale: 600)) { img, _, err in
            guard let img, err == nil else { return }
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

    // MARK: - Reassert timer

    private func startReassertTimer() {
        reassertTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.windows.forEach { $0.reassert() }
        }
    }

    // MARK: - Notifications

    @objc private func screensSleep() { windows.forEach { $0.pause() } }
    @objc private func screensWake() { windows.forEach { $0.reassert() } }
    @objc private func screensChanged() { buildWindows() }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
