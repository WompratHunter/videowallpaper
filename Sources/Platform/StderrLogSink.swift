import Application
import Core

// MARK: - Log sink
// Writes each event's log rendering (declared with the event in its context) as one timestamped stderr line, which
// the LaunchAgent routes to ~/Library/Logs/videowallpaper.log. An `os.Logger` sink can replace it later with no change
// to what is logged.

enum StderrLogSink {
    @MainActor
    static func attach(to coordinator: Coordinator) {
        coordinator.subscribe { event in
            guard let line = event.logLine else { return }
            Log.write(line.cause, line.message)
        }
    }
}
