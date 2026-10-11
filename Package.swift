// swift-tools-version: 6.0
import PackageDescription

// One target per bounded context (ADR 0001), meeting only in `Application`'s coordinator (ADR 0002). A context
// depends only on the shared kernel. `Platform` is the entry point: it composes the adapters and is the only target
// that knows every concrete type. The legacy `Core` (Foundation-only domain), `App` (AppKit/AVFoundation adapters)
// and `Analyser` targets hold the code still to move into its context; each later ticket moves its own files.
// Swift 6 language mode comes last.
// Each context's target and test target is one line of its own, so a context ticket adds a dependency on its own
// line without touching another's.
let contexts = ["Library", "Rotation", "Playback", "Presence", "Daylight", "Desktop"]
let contextDependencies = contexts.map { Target.Dependency(stringLiteral: $0) }
let contextTargets: [Target] = [
    .target(name: "Library", dependencies: ["SharedKernel"]),
    .target(name: "Rotation", dependencies: ["SharedKernel"]),
    .target(name: "Playback", dependencies: ["SharedKernel"]),
    .target(name: "Presence", dependencies: ["SharedKernel"]),
    .target(name: "Daylight", dependencies: ["SharedKernel"]),
    .target(name: "Desktop", dependencies: ["SharedKernel"])
]
let contextTestTargets: [Target] = [
    .testTarget(name: "LibraryTests", dependencies: ["Library", "SharedKernel"]),
    .testTarget(name: "RotationTests", dependencies: ["Rotation", "SharedKernel"]),
    .testTarget(name: "PlaybackTests", dependencies: ["Playback", "SharedKernel"]),
    .testTarget(name: "PresenceTests", dependencies: ["Presence", "SharedKernel"]),
    .testTarget(name: "DaylightTests", dependencies: ["Daylight", "SharedKernel", "TestSupport"]),
    .testTarget(name: "DesktopTests", dependencies: ["Desktop", "SharedKernel"])
]

let package = Package(
    name: "VideoWallpaper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "videowallpaper", targets: ["VideoWallpaper"]),
        .executable(name: "smoke", targets: ["Smoke"]),
        // What a thin Xcode app target (App Store phase) links to call `VideoWallpaperApp.run()`.
        .library(name: "VideoWallpaperPlatform", targets: ["Platform"])
    ],
    targets: contextTargets + contextTestTargets
        + [
            .target(name: "SharedKernel"),
            .target(name: "Application", dependencies: ["SharedKernel", "Core"] + contextDependencies),
            .target(
                name: "Platform",
                dependencies: ["Application", "App", "Core", "SharedKernel"] + contextDependencies,
                // The LaunchAgent plist `make install` writes, embedded so the launch-at-login adapter writes the same.
                resources: [.embedInCode("com.videowallpaper.plist.template")]),
            .executableTarget(name: "VideoWallpaper", dependencies: ["Platform"]),
            .target(
                name: "TestSupport",
                dependencies: ["Application", "Core", "SharedKernel"] + contextDependencies,
                path: "Tests/TestSupport"),
            .testTarget(
                name: "ApplicationTests",
                dependencies: ["Application", "TestSupport", "Core", "SharedKernel"] + contextDependencies),
            .testTarget(name: "PlatformTests", dependencies: ["Platform", "Application"]),
            // Legacy targets, emptied context by context.
            .target(name: "Core", dependencies: ["SharedKernel"] + contextDependencies),
            .target(name: "Analyser", dependencies: ["Core"]),
            .target(
                name: "App",
                dependencies: ["Core", "Analyser", "Application", "SharedKernel"] + contextDependencies),
            .executableTarget(name: "Smoke", dependencies: ["Core", "Analyser"], path: "Tests/Smoke"),
            .testTarget(name: "CoreTests", dependencies: ["Core", "SharedKernel"] + contextDependencies)
        ],
    swiftLanguageModes: [.v5]
)
