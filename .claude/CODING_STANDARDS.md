# Coding Standards

Swift-only, single-file macOS app. No Xcode project — compiled via `Makefile` with `swiftc`.

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

- Use `// MARK: - Section` to divide logical sections within a file; match existing markers (`Helpers`, `Window management`, `Folder watching`, etc.)
- Keep related logic together rather than splitting into multiple files unless a type exceeds ~150 lines
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

## Comments

- Only comment the **why**, not the what — non-obvious constraints, workarounds, subtle invariants
- `// MARK:` for sections; inline `//` for one-liners; no block comments in production code
