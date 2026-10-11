// MARK: - Log line
// Each context renders its own events as log lines (the event's single rendering); Platform's log sink writes them.
// The cause names what led to the line (`launch`, `wake`, `folder-change`, …).

public struct LogLine: Equatable, Sendable {
    public let cause: String
    public let message: String

    public init(cause: String, message: String) {
        self.cause = cause
        self.message = message
    }
}
