// swift-tools-version: 6.0
import PackageDescription

// One target per bounded context (ADR 0001), meeting only in `Application`'s coordinator (ADR 0002). A context
// depends only on the shared kernel. `Platform` is the entry point: it composes the adapters and is the only target
// that knows every concrete type. The legacy `Core` (Foundation-only domain), `App` (AppKit/AVFoundation adapters)
// and `Analyser` targets hold the code still to move into its context; each later ticket moves its own files.
// Swift 6 language mode comes last.
let contexts = ["Library", "Rotation", "Playback", "Presence", "Daylight", "Desktop"]
let contextDependencies = contexts.map { Target.Dependency(stringLiteral: $0) }

let package = Package(
    name: "VideoWallpaper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "videowallpaper", targets: ["VideoWallpaper"]),
        .executable(name: "smoke", targets: ["Smoke"])
    ],
    targets: contexts.map { .target(name: $0, dependencies: ["SharedKernel"]) }
        + contexts.map { .testTarget(name: "\($0)Tests", dependencies: [.init(stringLiteral: $0), "SharedKernel"]) }
        + [
            .target(name: "SharedKernel"),
            .target(name: "Application", dependencies: ["SharedKernel", "Core"] + contextDependencies),
            .target(
                name: "Platform",
                dependencies: ["Application", "App", "Core", "SharedKernel"] + contextDependencies),
            .executableTarget(name: "VideoWallpaper", dependencies: ["Platform"]),
            .target(
                name: "TestSupport",
                dependencies: ["Application", "Core", "SharedKernel"] + contextDependencies,
                path: "Tests/TestSupport"),
            .testTarget(
                name: "ApplicationTests",
                dependencies: ["Application", "TestSupport", "App", "Core", "SharedKernel"] + contextDependencies),
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
