import Foundation

// MARK: - Launch-at-login adapter

extension Composition {
    static func launchAtLogin() -> LaunchAgentLogin {
        LaunchAgentLogin(plistFile: AppFiles.launchAgentFile, home: NSHomeDirectory())
    }
}
