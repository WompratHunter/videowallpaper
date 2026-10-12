import AppKit

// MARK: - Wallpaper windows
// The windows port's adapter: one desktop-level window per screen. Windows only host the shared player's layers; all
// playback lives in the service.

@MainActor
package final class WallpaperWindows: WallpaperWindowsPort {
    package var onOcclusionChange: (OcclusionChange, Bool) -> Void = { _, _ in }

    private let player: SharedPlayer
    private var windows: [WallpaperWindow] = []
    private var occlusionObserver: NSObjectProtocol?

    package init(player: SharedPlayer) {
        self.player = player
    }

    deinit {
        occlusionObserver.map(NotificationCenter.default.removeObserver)
    }

    /// One window per connected screen; run at launch and whenever screens are added, removed or rearranged.
    package func rebuild() {
        // Swapped out before closing: a closing window's occlusion change must not count as the desktop covered.
        let old = windows
        windows = NSScreen.screens.map { WallpaperWindow(screen: $0, player: player) }
        old.forEach { $0.close() }
        // orderFront, not makeKeyAndOrderFront: a desktop window must never take keyboard focus.
        windows.forEach { $0.orderFront(nil) }
        applyOcclusion(change: .windowsBuilt(count: windows.count))
        observeOcclusion()
    }

    /// The window level and order can be lost across wake and Space switches.
    package func reassert() {
        windows.forEach { $0.reassert() }
    }

    // MARK: - Occlusion

    /// Started after the first build, so the launch state is reported once by the build itself.
    private func observeOcclusion() {
        guard occlusionObserver == nil else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] note in
            // Observed on the main queue, so `assumeIsolated` holds; windows post it on the main thread, where the
            // main queue delivers it synchronously, as before.
            MainActor.assumeIsolated { self?.occlusionChanged(note) }
        }
    }

    private func occlusionChanged(_ note: Notification) {
        guard let window = note.object as? WallpaperWindow, let index = windows.firstIndex(of: window) else { return }
        applyOcclusion(change: .screen(index: index, isVisible: window.occlusionState.contains(.visible)))
    }

    /// Covered only when every display's window is covered by opaque windows. Translucent ones (e.g. Ghostty)
    /// leave the window's occlusion state visible, so the video keeps playing behind them.
    private func applyOcclusion(change: OcclusionChange) {
        let isAllOccluded = isEveryWindowOccluded(visibility: windows.map { $0.occlusionState.contains(.visible) })
        onOcclusionChange(change, isAllOccluded)
    }
}

// MARK: - Per-screen wallpaper window

private final class WallpaperWindow: NSWindow {
    init(screen: NSScreen, player: SharedPlayer) {
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
