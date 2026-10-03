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

    var playbackSeconds: Double? {
        guard let time = player?.currentTime(), time.isNumeric else { return nil }
        return time.seconds
    }

    func stateReport(sinceSeconds earlier: Double?) -> PlayerStateReport {
        guard let player else { return .noPlayer }
        let item = player.currentItem
        return PlayerStateReport(
            playerStatus: name(of: player.status),
            itemStatus: item.map { name(of: $0.status) } ?? "none",
            itemError: (item?.error ?? player.error).map(describe),
            timeControl: name(of: player.timeControlStatus),
            waitingReason: player.reasonForWaitingToPlay?.rawValue,
            timeAdvanced: playbackAdvanced(from: earlier, to: playbackSeconds))
    }

    func reassert() {
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        orderBack(nil)
        if player?.timeControlStatus == .paused { player?.play() }
    }
}

// MARK: - AV state names

private func name(of status: AVPlayer.Status) -> String {
    switch status {
    case .unknown: return "unknown"
    case .readyToPlay: return "readyToPlay"
    case .failed: return "failed"
    @unknown default: return "rawValue\(status.rawValue)"
    }
}

private func name(of status: AVPlayerItem.Status) -> String {
    switch status {
    case .unknown: return "unknown"
    case .readyToPlay: return "readyToPlay"
    case .failed: return "failed"
    @unknown default: return "rawValue\(status.rawValue)"
    }
}

private func name(of status: AVPlayer.TimeControlStatus) -> String {
    switch status {
    case .paused: return "paused"
    case .waitingToPlayAtSpecifiedRate: return "waitingToPlayAtSpecifiedRate"
    case .playing: return "playing"
    @unknown default: return "rawValue\(status.rawValue)"
    }
}

private func describe(_ error: Error) -> String {
    let nsError = error as NSError
    return "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [WallpaperWindow] = []
    private var currentVideo: URL?
    private var folderWatch: DispatchSourceFileSystemObject?
    private var reassertTimer: Timer?
    private let wallpaperDir = URL(fileURLWithPath: NSString("~/Movies/LiveWallpaper").expandingTildeInPath)

    func applicationDidFinishLaunching(_ n: Notification) {
        Log.write("launch", "pid=\(ProcessInfo.processInfo.processIdentifier) screens=\(NSScreen.screens.count)")
        buildWindows()
        startFolderWatch()
        startReassertTimer()
        observeSystemEvents()
        logPlayerState(cause: "launch")
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

    // MARK: - Diagnostics

    /// Samples each player now and again a moment later, so the line records whether time actually advanced
    /// rather than trusting timeControlStatus, which can claim "playing" for a dead player.
    private func logPlayerState(cause: String) {
        let samples = windows.map { (window: $0, earlierSeconds: $0.playbackSeconds) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            let video = self?.currentVideo?.lastPathComponent ?? "none"
            for (index, sample) in samples.enumerated() {
                let report = sample.window.stateReport(sinceSeconds: sample.earlierSeconds)
                Log.write(cause, "screen=\(index) video=\(video) \(report)")
            }
            if samples.isEmpty { Log.write(cause, "screens=0 video=\(video) \(PlayerStateReport.noPlayer)") }
        }
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

    @objc private func screensSleep() {
        Log.write("screens-sleep", "pausing \(windows.count) player(s)")
        windows.forEach { $0.pause() }
    }

    @objc private func screensWake() {
        logPlayerState(cause: "screens-wake")
        windows.forEach { $0.reassert() }
    }

    @objc private func systemWake() { logPlayerState(cause: "wake") }
    @objc private func sessionActive() { logPlayerState(cause: "session-active") }
    @objc private func screenUnlocked() { logPlayerState(cause: "unlock") }
    @objc private func screensChanged() { buildWindows() }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
