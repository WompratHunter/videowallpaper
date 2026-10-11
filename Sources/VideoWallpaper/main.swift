import App
import AppKit

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
