import Foundation

// MARK: - Distributed lock signal
// The lock/unlock port's adapter: the distributed screen lock and unlock notifications, which the system posts on the
// main thread. They are undocumented; `LockSignalPort` describes the public fallback.

@MainActor
public final class DistributedLockSignal: NSObject, LockSignalPort {
    public var onChange: (Bool) -> Void = { _ in }

    override public init() {
        super.init()
    }

    public func start() {
        let center = DistributedNotificationCenter.default()
        // Unlock has no public NSWorkspace notification; this distributed one is what the system posts.
        center.addObserver(
            self, selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        // Lock is expected to occlude every window too; this keeps Unseen correct if it doesn't.
        center.addObserver(
            self, selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
    }

    @objc private func screenLocked() { onChange(true) }

    @objc private func screenUnlocked() { onChange(false) }
}
