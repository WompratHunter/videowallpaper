// swift-tools-version: 6.0
import PackageDescription

// Legacy layout while the code moves into one target per context (ADR 0001): Foundation-only `Core`, the AppKit
// `App`, and the AVFoundation `Analyser` shared by the app and the smoke runner. Swift 6 language mode comes last.
let package = Package(
    name: "VideoWallpaper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "videowallpaper", targets: ["VideoWallpaper"]),
        .executable(name: "smoke", targets: ["Smoke"])
    ],
    targets: [
        .target(name: "Core", path: "Sources/Core"),
        .target(name: "Analyser", dependencies: ["Core"], path: "Sources/Analyser"),
        .target(name: "App", dependencies: ["Core", "Analyser"], path: "Sources/App"),
        .executableTarget(name: "VideoWallpaper", dependencies: ["App"], path: "Sources/VideoWallpaper"),
        .executableTarget(name: "Smoke", dependencies: ["Core", "Analyser"], path: "Tests/Smoke"),
        .testTarget(name: "CoreTests", dependencies: ["Core"], path: "Tests/CoreTests")
    ],
    swiftLanguageModes: [.v5]
)
