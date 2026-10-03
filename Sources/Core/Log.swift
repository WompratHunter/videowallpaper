import Foundation

// MARK: - Logging
// The LaunchAgent routes stderr to ~/Library/Logs/videowallpaper.log. FileHandle writes go straight to
// the file descriptor, so lines land immediately instead of sitting in a stdio buffer when the app dies.

enum Log {
    static func write(_ cause: String, _ message: String) {
        FileHandle.standardError.write(Data(line(cause: cause, message: message).utf8))
    }

    static func line(cause: String, message: String, at date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = timeZone
        let singleLine = message.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
        return "\(formatter.string(from: date)) [\(cause)] \(singleLine)\n"
    }
}
