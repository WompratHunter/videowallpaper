# Coding Standards

Swift-only macOS app, built as a SwiftPM package (`Package.swift`, ADR 0001) that the `Makefile` drives with `swift build` / `swift test`. Its targets are laid out in Contexts and the Application layer below. While the code moves into its contexts, it has legacy targets: `Core` (`Sources/Core/`, Foundation-only), `App` (`Sources/App/`), the thin `VideoWallpaper` executable (`Sources/VideoWallpaper/main.swift`) and `Smoke` (`Tests/Smoke/`, which runs the Library context's analyser); legacy declarations used across targets are `package`. SwiftLint covers `Package.swift`, `Sources/` and `Tests/`. App code is split into modules (see Code Organisation); Foundation-only core logic lives in `Sources/Core/`; tests live in `Tests/`.

## Language & Platform

- A Swift 6 toolchain (`swift-tools-version: 6.0`) in Swift 5 language mode until the Swift 6 switch, macOS 14+ target
- Frameworks: AppKit, AVFoundation, CoreLocation, Dispatch
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

- The app is a set of deep modules, each a small interface over most of the logic. Modules never call each other: the coordinator (`Sources/Application/Coordinator*.swift`) is the only place they meet, routing system notifications, the shared 5 s tick and Preferences to each module and carrying one module's events to another (see Contexts and the Application layer)
  - **Player** (`Player*.swift`): the shared player, the layers in every window, health checks and Recovery
  - **Library** (the Library context, `Sources/Library/`): the Wallpaper folder watch, settle check, Analysis, the Video catalogue and its Posters, behind folder, analyser and store ports
  - **WallpaperWindows** (`WallpaperWindows*.swift`): one desktop-level window per screen, hosting the Player's layers, and occlusion
  - **Visibility** (`Visibility*.swift`): Unseen, Veiled or Visible, with a change callback
  - **Rotation** (`Rotation*.swift`): the switch scheduler, reading the inputs the coordinator connects (time, eligible videos, Presence, `Mode`, Daylight) for Core's `RotationState`, returning the switch and publishing `RotationEvent`s
  - **Daylight** (`Sources/Daylight/`, a context): `DaylightService` works out where Daylight is computed for (Location Services fix, cache, time zone) and the appearance fallback, behind the location, time-zone-places, location-cache and appearance ports; Platform builds the CoreLocation and AppKit adapters and the debug location and clock
  - **DesktopPictures** (`DesktopPictures.swift`): recording, setting and restoring the system desktop picture
- A module talks to the outside through its methods and `on…` callback properties (typed `onEvent` once its events exist) that the coordinator sets; it does not hold references to other modules (a module may be given another as a dependency only to host it, as WallpaperWindows hosts the Player's layers)
- A module may span several files (one type plus extensions, or small internal helper types) when it grows past ~150 lines per type or ~400 per file; name the files after the module (`Player…`, `Library…`)
- Core logic is split per area the same way, one file per area named for it (e.g. `Recovery`, `PlaybackGate`, `PlayerStateReport` for Player; `WallpaperFolder`, `PosterFiles`, `Flash` for Library; `VisibilityClassification`; `Rotation`; `Daylight` for sun position, the Daylight curve and the location fallback; `Footprint` for desktop-picture record and restore; `Log`), each with its own test suite
- Use `// MARK: - Section` to divide logical sections within a file; match existing markers (`Folder watching`, `Recovery`, `Notifications`, etc.)
- Free functions are fine for stateless helpers (`newestVideo(in:)`)

## Contexts and the Application layer

The target layout every context ticket follows (ADR 0001, ADR 0002); the full rewrite of these standards comes once the legacy targets are gone.

- **Shared kernel** (`Sources/SharedKernel/`): only the types contexts must agree on: `VideoID` (the file name), `Version` (size and mtime in ms), `EligibleVideo`, `Presence`, `PosterImage`, `LogLine` and the `Uptime` time value. Nothing else is shared
- **Contexts** (`Sources/{Library,Rotation,Playback,Presence,Daylight,Desktop}/`): one target each, depending only on the shared kernel. A context's domain stays `internal`; only its events, snapshot slice, commands and port protocols are `public`. Each declares `<Context>Event` with its single log rendering (`logLine`) and `<Context>Slice`. A context never imports another: `make` builds with `--explicit-target-dependency-import-check error`, so an undeclared import fails the build
- **Application** (`Sources/Application/`, Foundation-only, `@MainActor`): depends on contexts and port protocols, never on adapters
  - `Coordinator.swift` runs launch and the tick across contexts, delivers `AppEvent`s in order and republishes the `AppSnapshot` when it changes
  - `Coordinator+<Context>.swift` holds that context's routes: what it hears, where its events go, and the commands other routes issue to it (`library…`, `rotation…`, `playback…` helpers). Routes into another context go through that context's helpers, so each ticket edits its own file
  - `AppEvent` has one case per context wrapping the context's own event enum, plus `ApplicationEvent` for commands; `AppSnapshot` has one slice per context plus `Preferences`
  - Ports are protocols here or in the owning context (`ClockPort`, `SettingsPort`, `PowerPort`); `Ports/<Context>Service.swift` is a temporary seam over a legacy adapter that the context's ticket replaces with the context's own service
  - Ordering rules are written in the routes: Dwell hears of a lock, sleep or session change before Presence; a folder change reaches Rotation before Playback; every video change sets its Poster, guarded against a stale one; a Presence change asks Rotation to decide at once
- **Platform** (`Sources/Platform/`): the only target that knows every concrete type. `AppDelegate` observes notifications, owns the tick's `SystemClock` and forwards to the coordinator; `Composition+<Context>.swift` builds that context's adapters; `AppFiles` holds every path, handed to modules when they are built; `StderrLogSink` writes events' log lines; `VideoWallpaperApp.run()` is the public entry point
- **Moving a context in**: name its public service `<Context>Service`, the name of the temporary seam it replaces, and make it a class (the coordinator sets its `onEvent`), so `Coordinator.swift` (which already imports every context), `Composition.swift` and the harness's `Coordinator(...)` call compile unchanged. A context can't reach legacy `Core`'s `Log`: every line it writes becomes an event with a `logLine`. In `Package.swift` each context and context test target is one line; add a dependency on your own line only
- **Module and type names**: never give a type its module's name. The kernel's `Presence` type shadows the `Presence` module, so `Presence.X` means a member of the type: write `SharedKernel.Presence` when you must qualify, and don't name a type `Library` inside the Library target
- **Tests**: `Tests/<Context>Tests/` per context, `Tests/ApplicationTests/` for the coordinator, commands, events and snapshot on fakes, and `Tests/TestSupport/` for fakes (`FakeClock`, `FakeSettings`, one file per context's fakes)

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
- A line that has moved onto events is the event's `logLine` in its context, written by Platform's `StderrLogSink`; the module no longer writes it
- Never `print` (lint bans it); every line names its cause (`launch`, `wake`, `unlock`, …)

## Testing

- Harness: swift-testing under `swift test` (`make test`), no XCTest. New tests are native `@Test`s in the context's test target, or in `Tests/ApplicationTests/` when they drive the coordinator
- The legacy suites use `check(_:_:)` / `checkEqual(_:_:)` from `Tests/CoreTests/Check.swift`; a failed check records a swift-testing issue, which fails the run
- One suite file per Core area (`Tests/CoreTests/<Area>Tests.swift`) exposing `run<Area>Tests()`, run by its context's test in `Tests/CoreTests/LegacySuites+<Context>.swift`; add checks to the matching suite rather than a new one
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
