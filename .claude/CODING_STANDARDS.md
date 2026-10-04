# Coding Standards

Swift-only macOS app. No Xcode project — compiled via `Makefile` with `swiftc`, which builds every `Sources/App/*.swift` and `Sources/Core/*.swift` file (entry file `Sources/App/main.swift`); SwiftLint covers `Sources/` and `Tests/`. App code is split into modules (see Code Organisation); Foundation-only core logic lives in `Sources/Core/`; tests live in `Tests/`.

## Language & Platform

- Swift 5.9+, macOS 14+ target
- Frameworks: AppKit, AVFoundation, Dispatch
- No SwiftUI, no third-party dependencies

## Naming (Apple Swift API Design Guidelines)

- Types: `UpperCamelCase` — `WallpaperWindow`, `AppDelegate`
- Functions, properties, variables: `lowerCamelCase` — `buildWindows()`, `currentVideo`
- Boolean properties read as assertions: `isOpaque`, `hasShadow`, `ignoresMouseEvents`
- Acronyms: all-caps when standalone (`URL`, `CGRect`), title-case inside a compound name (`fileURL`)
- Omit redundant type words: `newestVideo(in:)` not `newestVideoURL(in:)`

## Types & Access Control

- Mark leaf classes `final`; default to `private` for properties and helpers
- Expose only what a caller genuinely needs — keep the public surface minimal
- Use `NSObject` subclasses only where AppKit/ObjC interop requires it (`AppDelegate`, `@objc` selectors)

## Error Handling

- Use `try?` for recoverable filesystem and AV operations where failure is silent-by-design
- Never silently swallow errors that indicate a broken invariant — log or `fatalError` those
- Validate at system boundaries (file paths, AV asset URLs); trust internal state

## Memory & Threading

- Always capture `[weak self]` in closures stored beyond the current scope (timers, dispatch sources, notification handlers)
- Route UI and window mutations to the main queue/actor; AV callbacks arrive on background queues
- Cancel `DispatchSource` and invalidate `Timer` on teardown to avoid leaks

## Code Organisation

- The app is a set of deep modules, each a small interface over most of the logic. Modules never call each other: `Sources/App/main.swift` (the app delegate) is the only place they meet, connecting system notifications, the shared 5 s tick and settings reads to each module and carrying one module's callbacks to another
  - **Player** (`Player*.swift`): the shared player, the layers in every window, health checks and Recovery
  - **Library** (`Library*.swift`): the Wallpaper folder watch, settle check, the video to play and its Posters
  - **WallpaperWindows** (`WallpaperWindows*.swift`): one desktop-level window per screen, hosting the Player's layers, and occlusion
  - **Visibility** (`Visibility*.swift`): Unseen, Veiled or Visible, with a change callback
  - **Rotation** (`Rotation*.swift`): the switch scheduler, gathering Dwell, Visibility, eligible videos, `Mode` and the appearance for Core's `RotationState`, with an `onSwitch` callback
  - `DesktopPictures.swift`: app paths (`AppFiles`) and the system desktop picture, used by the wiring
- A module talks to the outside through its methods and `on…` callback properties that the wiring sets; it does not hold references to other modules (a module may be given another as a dependency only to host it, as WallpaperWindows hosts the Player's layers)
- A module may span several files (one type plus extensions, or small internal helper types) when it grows past ~150 lines per type or ~400 per file; name the files after the module (`Player…`, `Library…`)
- Core logic is split per area the same way, one file per area named for it (e.g. `Recovery`, `PlaybackGate`, `PlayerStateReport` for Player; `WallpaperFolder`, `PosterFiles`, `Flash` for Library; `VisibilityClassification`; `Rotation`; `Footprint` for desktop-picture record and restore; `Log`), each with its own test suite
- File names must be unique across `Sources/` and `Tests/`, because `swiftc` compiles them as one module
- Use `// MARK: - Section` to divide logical sections within a file; match existing markers (`Folder watching`, `Recovery`, `Notifications`, etc.)
- Free functions are fine for stateless helpers (`newestVideo(in:)`)

## AppKit / Window Layer

- Desktop-level windows: `CGWindowLevelForKey(.desktopWindow)` — never hardcode raw level integers
- Required collection behavior for wallpapers: `.canJoinAllSpaces`, `.stationary`, `.ignoresCycle`
- Always set `isReleasedWhenClosed = false` on manually managed windows
- Reassert window level after wake/space-switch; don't assume the level persists across system events

## AVFoundation

- Use `AVQueuePlayer` + `AVPlayerLooper` for seamless looping
- Mute playback (`isMuted = true`) and disable display sleep prevention (`preventsDisplaySleepDuringVideoPlayback = false`) for a background wallpaper
- Release the old looper before creating a new one to avoid competing playback

## Formatting

- 4-space indentation, no tabs
- Opening brace on the same line; closing brace on its own line
- One blank line between methods; no blank lines inside short methods
- Trailing closures for single-closure arguments; named labels for multi-closure calls
- No trailing whitespace; files end with a newline

## Logging

- Log with `Log.write(cause, message)` (`Sources/Core/Log.swift`): one timestamped line to unbuffered stderr, which the LaunchAgent routes to `~/Library/Logs/videowallpaper.log`
- Never `print` (lint bans it); every line names its cause (`launch`, `wake`, `unlock`, …)

## Testing

- Harness: a plain `swiftc`-compiled runner in `Tests/` — no SwiftPM, no XCTest. `make test` compiles `Sources/Core/*.swift` with `Tests/*.swift` into `.build/tests` and runs it
- Use `check(_:_:)` / `checkEqual(_:_:)` from `Tests/Check.swift`; the runner exits non-zero if any check fails
- One suite file per Core area (`Tests/<Area>Tests.swift`) exposing `run<Area>Tests()`, registered in `Tests/main.swift`; add checks to the matching suite rather than a new one
- The seam is `Sources/Core/`: Foundation-only pure functions and value types. Anything that is a decision (Recovery, backoff, settle, flash counting, Rotation pick, visibility, log formatting) belongs there and must be tested; AppKit/AVFoundation code only gathers inputs and applies results
- State transitions belong in Core too: when a decision depends on state the app also mutates (e.g. reading "is recovering" vs resetting the backoff), Core takes the current state and returns the action plus the next state, so ordering is tested; app code only applies the returned action
- Tests assert the decision returned for given inputs, not internal state or call order; inject clocks and RNGs rather than reading them
- Gate: `make build` runs lint (`--strict`), then tests, then compiles; any failure stops the build and `make install`

## Comments

- Only comment the **why**, not the what — non-obvious constraints, workarounds, subtle invariants
- `// MARK:` for sections; inline `//` for one-liners; no block comments in production code

## Makefile

- Quote every path in recipes (`"$(APP)"`); destructive recipes (`rm -rf`, `defaults delete`) name explicit app-owned paths only, with no globs, and guard against an empty or relative `HOME`

## Invariants

- Never black: in every state (launch, Analysis pending, Recovery, Low Power Mode, fades, no eligible video) a Poster or a playing video is on screen; the black window background is only acceptable before any Poster has ever existed
