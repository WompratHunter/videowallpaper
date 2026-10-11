import Application
import Foundation

// MARK: - Fake launch at login
// In-memory Launch at login state, on by default like today's install. Set `failure` to make the next change fail.

package final class FakeLaunchAtLogin: LaunchAtLoginPort {
    /// Its `reason` is the error's description, so it reads back as the command's failure reason.
    package struct Failure: LocalizedError {
        package let reason: String

        package init(_ reason: String) {
            self.reason = reason
        }

        package var errorDescription: String? { reason }
    }

    package var isEnabled: Bool
    package var failure: Failure?

    package init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    package func setEnabled(_ isEnabled: Bool) throws {
        if let failure { throw failure }
        self.isEnabled = isEnabled
    }
}
