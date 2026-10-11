import Foundation
import Platform
import Testing

// MARK: - LaunchAgent launch at login
// The adapter on a temporary folder, never the real ~/Library/LaunchAgents: on writes exactly what `make install`
// writes, off removes it, and neither needs the other first.

final class LaunchAgentLoginTests {
    private static let template = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Platform/com.videowallpaper.plist.template")
    private static let home = "/Users/some user"

    private let folder: URL
    private let plistFile: URL
    private let agent: LaunchAgentLogin

    init() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchAgentLoginTests-\(UUID().uuidString)", isDirectory: true)
        // The LaunchAgents folder doesn't exist yet: turning on creates it.
        plistFile = folder.appendingPathComponent("LaunchAgents/com.videowallpaper.plist")
        agent = LaunchAgentLogin(plistFile: plistFile, home: Self.home)
    }

    /// Each test gets its own instance, so this runs after every test, however it ends.
    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func onWritesWhatMakeInstallWrites() throws {
        #expect(agent.isEnabled == false)

        try agent.setEnabled(true)

        #expect(agent.isEnabled)
        #expect(try Data(contentsOf: plistFile) == makeInstallOutput())
        let plist = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: plistFile), format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == "com.videowallpaper")
        #expect(plist["ProgramArguments"] as? [String]
            == ["\(Self.home)/Applications/VideoWallpaper.app/Contents/MacOS/videowallpaper"])
    }

    @Test func offRemovesThePlist() throws {
        try agent.setEnabled(true)

        try agent.setEnabled(false)

        #expect(agent.isEnabled == false)
        #expect(FileManager.default.fileExists(atPath: plistFile.path) == false)
    }

    @Test func eachStateCanBeSetTwice() throws {
        try agent.setEnabled(false)
        #expect(agent.isEnabled == false)

        try agent.setEnabled(true)
        try agent.setEnabled(true)
        #expect(try Data(contentsOf: plistFile) == makeInstallOutput())
    }

    @Test func anUnwritableFolderThrows() throws {
        // A file where the LaunchAgents folder should be.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: plistFile.deletingLastPathComponent())

        #expect(throws: (any Error).self) { try agent.setEnabled(true) }
        #expect(agent.isEnabled == false)
    }

    /// The Makefile's own command on the template, so the two can't drift apart.
    private func makeInstallOutput() throws -> Data {
        let sed = Process()
        sed.executableURL = URL(fileURLWithPath: "/usr/bin/sed")
        sed.arguments = ["s|__HOME__|\(Self.home)|g", Self.template.path]
        let output = Pipe()
        sed.standardOutput = output
        try sed.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        sed.waitUntilExit()
        try #require(sed.terminationStatus == 0)
        return data
    }
}
