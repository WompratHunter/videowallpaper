import AppKit

// MARK: - App delegate
// Wiring: the only place modules meet. It connects system notifications and the shared tick to Player, Library,
// WallpaperWindows, Visibility and the Rotation, and carries each module's callbacks to the others; decisions live in
// the modules.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = Player()
    private let library = Library(directory: AppFiles.wallpaperDirectory, analysisCache: AppFiles.analysisCacheFile)
    private lazy var windows = WallpaperWindows(player: player)
    private let visibility = Visibility()
    /// Created at launch: the folder's videos then join the Rotation as their Analysis finishes, without counting as
    /// newly added.
    private lazy var rotation = RotationScheduler(
        directory: AppFiles.wallpaperDirectory,
        present: Set(Library.videoSnapshot(of: AppFiles.wallpaperDirectory).keys),
        dwellScale: RotationScheduler.debugDwellScale)
    private var tickTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        Log.write("launch", "pid=\(ProcessInfo.processInfo.processIdentifier) screens=\(NSScreen.screens.count)")
        connectModules()
        // Recorded before anything can change the desktop picture; screens connected later are recorded before the
        // next Poster is set.
        DesktopPictures.recordOriginals()
        // Settled videos are known before the first pick and its saved Poster; Low Power Mode is known before any
        // Analysis starts or player is built.
        library.isPowerSaving = ProcessInfo.processInfo.isLowPowerModeEnabled
        library.start()
        rotation.start()
        // Unscreened videos never play, so until the first Analysis the underlay is a still: never black.
        let underlay = library.launchUnderlay(
            toPlay: rotation.video, desktopPicture: DesktopPictures.mainScreenPicture())
        if let underlay { player.setPoster(underlay) }
        player.apply(.lowPower(ProcessInfo.processInfo.isLowPowerModeEnabled))
        windows.rebuild()
        player.start()
        startTickTimer()
        observeSystemEvents()
        player.verifyPlayback(cause: "launch")
    }

    private func connectModules() {
        player.videoProvider = { [weak self] in
            self?.rotation.refresh(cause: "rebuild")
            return self?.rotation.video
        }
        library.flashOverrides = { UserDefaults.standard.stringArray(forKey: "FlashOverride") ?? [] }
        // Every change of video (Rotation, Recovery or folder change) lands here, so the Poster always follows it.
        player.onVideoChange = { [weak self] url in self?.showPoster(for: url) }
        // A renamed or deleted Current video goes through Recovery (logged, Poster during the gap), because
        // AVFoundation may otherwise keep playing the old open file. A new video only joins the Rotation here.
        library.onChange = { [weak self] in
            guard let self else { return }
            let change = self.rotation.refresh(cause: "folder-change")
            self.player.folderChanged(toPlay: self.rotation.video, fade: change?.fade ?? Crossfade.quickDuration)
        }
        windows.onOcclusionChange = { [weak self] isAllOccluded in
            self?.player.apply(.allWindowsOccluded(isAllOccluded))
            self?.noteVisibility(.everyWindowOccluded(isAllOccluded), cause: "occlusion")
        }
        connectRotation()
    }

    private func connectRotation() {
        rotation.eligibleVideos = { [weak self] in self?.library.eligibleVideos() ?? [] }
        rotation.visibility = { [weak self] in self?.visibility.state ?? .visible }
        rotation.checkVeil = { [weak self] in self?.visibility.checkVeil() ?? .visible }
        rotation.isPowerSaving = { ProcessInfo.processInfo.isLowPowerModeEnabled }
        rotation.modeSetting = { UserDefaults.standard.string(forKey: "Mode") }
        rotation.onSwitch = { [weak self] video, fade in self?.player.play(video, fade: fade) }
        // An Unseen or Veiled moment is a switch point, acted on at once rather than at the next tick.
        visibility.onChange = { [weak self] _ in self?.rotation.evaluate(cause: "visibility") }
    }

    /// Dwell hears of a lock, sleep or session change before Visibility reports it, so a switch on locking counts
    /// Dwell only up to the lock.
    private func noteVisibility(_ event: VisibilityEvent, cause: String) {
        rotation.apply(event)
        visibility.apply(event, cause: cause)
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
            self?.rotation.evaluate(cause: "tick")
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
        noteVisibility(.screensAsleep(true), cause: "screens-sleep")
    }

    @objc private func screensWake() {
        windows.reassert()
        player.resetBackoff(on: .wake)
        player.apply(.screensAsleep(false))
        noteVisibility(.screensAsleep(false), cause: "screens-wake")
        player.verifyPlayback(cause: "screens-wake")
    }

    /// Posted on an arbitrary queue; the player is main-thread only.
    @objc private func powerStateChanged() {
        DispatchQueue.main.async { [weak self] in
            let isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
            Log.write("power", "low-power=\(isOn ? "on" : "off")")
            self?.player.apply(.lowPower(isOn))
            self?.library.isPowerSaving = isOn
        }
    }

    @objc private func systemWake() {
        player.resetBackoff(on: .wake)
        player.verifyPlayback(cause: "wake")
    }

    @objc private func sessionActive() {
        noteVisibility(.sessionInactive(false), cause: "session-active")
        player.verifyPlayback(cause: "session-active")
    }

    @objc private func sessionInactive() { noteVisibility(.sessionInactive(true), cause: "session-inactive") }

    @objc private func screenLocked() { noteVisibility(.locked(true), cause: "lock") }

    @objc private func screenUnlocked() {
        noteVisibility(.locked(false), cause: "unlock")
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
