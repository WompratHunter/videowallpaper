import AppKit

// MARK: - App delegate
// Wiring: the only place modules meet. It connects system notifications and the shared tick to Player, Library,
// WallpaperWindows and Visibility, and carries each module's callbacks to the others; decisions live in the modules.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = Player()
    private let library = Library(directory: AppFiles.wallpaperDirectory)
    private lazy var windows = WallpaperWindows(player: player)
    private let visibility = Visibility()
    private var tickTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        Log.write("launch", "pid=\(ProcessInfo.processInfo.processIdentifier) screens=\(NSScreen.screens.count)")
        connectModules()
        // Recorded before anything can change the desktop picture; screens connected later are recorded before the
        // next Poster is set.
        DesktopPictures.recordOriginals()
        // Settled videos are known before the first pick and its saved Poster; Low Power Mode is known before any
        // player is built.
        library.start()
        if let video = library.videoToPlay(), let image = library.savedPoster(for: video) { player.setPoster(image) }
        player.apply(.lowPower(ProcessInfo.processInfo.isLowPowerModeEnabled))
        windows.rebuild()
        player.start()
        startTickTimer()
        observeSystemEvents()
        player.verifyPlayback(cause: "launch")
    }

    private func connectModules() {
        player.videoProvider = { [weak self] in self?.library.videoToPlay() }
        player.onVideoChange = { [weak self] url in self?.showPoster(for: url) }
        // A renamed or deleted Current video goes through Recovery (logged, Poster during the gap), because
        // AVFoundation may otherwise keep playing the old open file.
        // Until Rotation decides switches, a new newest video crossfades in.
        library.onChange = { [weak self] video in
            self?.player.folderChanged(newest: video, fade: Crossfade.quickDuration)
        }
        windows.onOcclusionChange = { [weak self] isAllOccluded in
            self?.player.apply(.allWindowsOccluded(isAllOccluded))
            self?.visibility.apply(.everyWindowOccluded(isAllOccluded), cause: "occlusion")
        }
    }

    /// The Current video's Poster goes under the video and becomes the desktop picture on every screen.
    private func showPoster(for video: URL) {
        library.poster(for: video) { [weak self] poster in
            guard let self, self.player.video == video else { return false }
            self.player.setPoster(poster.image)
            if let file = poster.file { DesktopPictures.setPoster(file) }
            return true
        }
    }

    private func startTickTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.windows.reassert()
            self?.player.healthTick()
        }
        timer.tolerance = 2
        tickTimer = timer
    }
}

// MARK: - Notifications

extension AppDelegate {
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
        workspace.addObserver(
            self, selector: #selector(sessionInactive),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        // Unlock has no public NSWorkspace notification; this distributed one is what the system posts.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        // Lock is expected to occlude every window too; this keeps Unseen correct if it doesn't.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerStateChanged),
            name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    @objc private func screensSleep() {
        Log.write("screens-sleep", "pausing shared player")
        player.apply(.screensAsleep(true))
        visibility.apply(.screensAsleep(true), cause: "screens-sleep")
    }

    @objc private func screensWake() {
        windows.reassert()
        player.resetBackoff(on: .wake)
        player.apply(.screensAsleep(false))
        visibility.apply(.screensAsleep(false), cause: "screens-wake")
        player.verifyPlayback(cause: "screens-wake")
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

    @objc private func sessionActive() {
        visibility.apply(.sessionInactive(false), cause: "session-active")
        player.verifyPlayback(cause: "session-active")
    }

    @objc private func sessionInactive() { visibility.apply(.sessionInactive(true), cause: "session-inactive") }

    @objc private func screenLocked() { visibility.apply(.locked(true), cause: "lock") }

    @objc private func screenUnlocked() {
        visibility.apply(.locked(false), cause: "unlock")
        player.resetBackoff(on: .unlock)
        player.verifyPlayback(cause: "unlock")
    }

    @objc private func screensChanged() { windows.rebuild() }
}

// MARK: - Entry point

let app = NSApplication.shared
// Run by `make uninstall` after the LaunchAgent is unloaded: restore and exit, with no windows or player.
if CommandLine.arguments.contains("--restore-wallpaper") {
    exit(DesktopPictures.restoreOriginals())
}
if CommandLine.arguments.contains("--check-veil") { Visibility.runVeilProbe() }
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
