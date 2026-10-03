import AppKit

// MARK: - Wallpaper windows
// One desktop-level window per screen. Windows only host the shared player's layers; all playback lives in Player.

final class WallpaperWindows {
    /// Called with whether every window is covered by opaque windows, on each build and occlusion change.
    var onOcclusionChange: (Bool) -> Void = { _ in }

    private let player: Player
    private var windows: [WallpaperWindow] = []
    private var occlusionObserver: NSObjectProtocol?

    init(player: Player) {
        self.player = player
    }

    deinit {
        occlusionObserver.map(NotificationCenter.default.removeObserver)
    }

    /// One window per connected screen; run at launch and whenever screens are added, removed or rearranged.
    func rebuild() {
        // Swapped out before closing: a closing window's occlusion change must not count as the desktop covered.
        let old = windows
        windows = NSScreen.screens.map { WallpaperWindow(screen: $0, player: player) }
        old.forEach { $0.close() }
        // orderFront, not makeKeyAndOrderFront: a desktop window must never take keyboard focus.
        windows.forEach { $0.orderFront(nil) }
        applyOcclusion(change: "windows=\(windows.count)")
        observeOcclusion()
    }

    /// The window level and order can be lost across wake and Space switches.
    func reassert() {
        windows.forEach { $0.reassert() }
    }

    // MARK: - Occlusion

    /// Started after the first build, so the launch state is logged once by the build itself.
    private func observeOcclusion() {
        guard occlusionObserver == nil else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: nil
        ) { [weak self] note in
            self?.occlusionChanged(note)
        }
    }

    private func occlusionChanged(_ note: Notification) {
        guard let window = note.object as? WallpaperWindow, let index = windows.firstIndex(of: window) else { return }
        applyOcclusion(change: "screen=\(index) visible=\(window.occlusionState.contains(.visible) ? "yes" : "no")")
    }

    /// Pauses only when every display's window is covered by opaque windows. Translucent ones (e.g. Ghostty)
    /// leave the window's occlusion state visible, so the video keeps playing behind them.
    private func applyOcclusion(change: String) {
        let isAllOccluded = isEveryWindowOccluded(visibility: windows.map { $0.occlusionState.contains(.visible) })
        Log.write("occlusion", "\(change) all-occluded=\(isAllOccluded ? "yes" : "no")")
        onOcclusionChange(isAllOccluded)
    }
}

// MARK: - Per-screen wallpaper window

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
