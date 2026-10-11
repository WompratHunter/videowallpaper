import App
import AppKit

// MARK: - Entry point
// Public so a thin Xcode app target (App Store phase) can start the same app the executable does.

public enum VideoWallpaperApp {
    /// Call from the main thread (the process's top-level code); it never returns.
    public static func run() -> Never {
        MainActor.assumeIsolated { runOnMainActor() }
    }

    @MainActor
    private static func runOnMainActor() -> Never {
        let app = NSApplication.shared
        // Run by `make uninstall` after the LaunchAgent is unloaded: restore and exit, with no windows or player.
        if CommandLine.arguments.contains("--restore-wallpaper") {
            exit(Composition.desktop().restoreOriginals())
        }
        if CommandLine.arguments.contains("--check-veil") { Visibility.runVeilProbe() }
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        exit(0)
    }
}
