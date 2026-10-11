import Application
import Foundation

// MARK: - LaunchAgent launch at login
// Today's launch-at-login adapter: the user's LaunchAgent plist. On writes it with exactly what `make install` writes
// (the template beside this file, embedded in this target, is the one the Makefile seds); off removes it, so the app
// doesn't start at the next login. It never calls `launchctl`: loading would start a second app and unloading would
// stop this one, so launchd keeps today's job until logout and the change takes effect at the next login. The App
// Store phase replaces it with `SMAppService` behind the same port.

package final class LaunchAgentLogin: LaunchAtLoginPort {
    private let plistFile: URL
    private let home: String

    /// `home` replaces `__HOME__` in the template, as `make install` does with `$(HOME)`.
    package init(plistFile: URL, home: String) {
        self.plistFile = plistFile
        self.home = home
    }

    package var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistFile.path)
    }

    package func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try FileManager.default.createDirectory(
                at: plistFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plist().write(to: plistFile, options: .atomic)
        } else {
            do {
                try FileManager.default.removeItem(at: plistFile)
            } catch CocoaError.fileNoSuchFile {
                // Already off.
            }
        }
    }

    /// The plist's content: `make install`'s `sed 's|__HOME__|$(HOME)|g'` on the same template.
    private func plist() throws -> Data {
        guard let template = String(bytes: PackageResources.com_videowallpaper_plist_template, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return Data(template.replacingOccurrences(of: "__HOME__", with: home).utf8)
    }
}
