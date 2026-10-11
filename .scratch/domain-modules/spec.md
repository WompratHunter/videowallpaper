# Spec: Domain modules: bounded contexts, application layer and platform ports

Status: ready-for-agent

Sources: domain grilling (2026-10-11), user answers Q1–Q18 (all as recommended), App Store sandbox research (same session). Vocabulary per `CONTEXT.md`. Decisions per `docs/adr/0001-swiftpm-targets-per-context.md` and `docs/adr/0002-contexts-meet-in-one-coordinator.md`. Standards per `.claude/CODING_STANDARDS.md`, which this spec amends.

## Problem Statement

VideoWallpaper started as a proof of concept I install with `make install` and control by dropping files into a folder and typing `defaults write`. I want to turn it into something I can eventually ship on the Mac App Store, with a real UI (a menu bar extra and a settings window) in the next phase.

The current code can't take a UI. The app's state is private inside a few large adapter classes, so a UI couldn't ask what is playing, why it switched, which videos are Excluded or still being analysed, or whether Recovery is resting. Modules tell each other only that "something changed", and the log file is the only record of what happened. Settings are raw string keys read in the wiring. "Video" means a file name in one place, a URL in another, a path in a third and a path-size-date key in a fourth. Nothing in the build stops one part of the code from reaching into another's internals.

The App Store adds its own pressure. A sandboxed app can't install a LaunchAgent, can't read a hard-coded folder without the user's grant, can't run an uninstall script to restore my desktop picture, and logs differently. If every one of those touchpoints is tangled into domain code, the App Store phase becomes a second rewrite.

## Solution

The app is reorganised around its domain, with the behaviour I see unchanged. It is split into six bounded contexts: Library, Rotation, Playback, Presence, Daylight and Desktop. Each is its own compiler-enforced module, and they meet only in one coordinator in an Application layer.

The Application layer is what a future UI will talk to:
- a set of commands;
- a snapshot of everything worth showing;
- a stream of typed domain events, which the log is now written from.

Every macOS touchpoint sits behind a port, with today's behaviour as its adapter: folder access, launch at login, the desktop picture, logging, location, settings and lock detection. The App Store phase can then swap adapters one at a time without touching domain code.

The commands the minimum App Store UI will need exist now and are tested headlessly, even though nothing calls them yet:
- Set Mode
- Set FlashOverride
- Enable / Disable
- Choose Wallpaper folder
- Set Launch at login

Disabling or quitting the app puts my own desktop picture back, so restoring no longer depends on `make uninstall`.

## User Stories

**Behaviour is preserved**

1. As a user, I want the Live wallpaper to look and behave exactly as before after this refactor (never black, Rotation, Dwell, crossfades, Daylight, Recovery, Low Power Mode), so that restructuring costs me nothing.
2. As a user, I want my existing `Mode` and `FlashOverride` settings to keep working unchanged, so that nothing I've configured is lost.
3. As a user, I want my Analysis cache, Posters, recorded original desktop pictures and cached location to carry over without re-analysis, so that the upgrade is invisible.
4. As a user, I want `make install` and `make uninstall` to keep working, so that my install and removal workflow doesn't change in this phase.
5. As a user, I want the log to keep the same lines it has today (same causes, same fields), so that I can still diagnose problems the way I do now.
6. As a user, I want `make build` to keep refusing to build when lint or any test fails, so that a broken build can never be installed.

**Commands a future UI will issue**

7. As a future UI, I want a Set Mode command, so that a Mode picker changes the Rotation without anyone editing `defaults`.
8. As a future UI, I want a Set FlashOverride command for one Video, so that a toggle can let an Excluded Video play or stop it again.
9. As a user, I want a FlashOverride change to take effect at once (an overridden Video joins the Rotation; a Video whose override is removed leaves it), so that a toggle feels immediate.
10. As a future UI, I want an Enable / Disable command, so that one switch turns the Live wallpaper on and off.
11. As a user, I want Disable to remove the Live wallpaper windows, stop playback and put my own desktop picture back on every screen, so that turning it off leaves my Mac as it was.
12. As a user, I want Enable to record my current desktop picture again before setting the Poster, so that a picture I chose while it was Disabled is the one restored next time.
13. As a user, I want quitting the app to behave like Disable, so that my own desktop picture is back whenever the app isn't running by choice.
14. As a user, I want Enabled or Disabled to be remembered across relaunches, so that a Disabled wallpaper stays off after a restart.
15. As a user, I want Analysis to keep going while Disabled (Low Power Mode permitting), so that Enabling later shows screened videos straight away.
16. As a future UI, I want a Choose Wallpaper folder command, so that a folder picker can point the app at any folder.
17. As a user, I want choosing a new Wallpaper folder to switch the Rotation to that folder's Videos (the Poster covers the gap), so that the change is immediate and never black.
18. As a user, I want the default Wallpaper folder to stay `~/Movies/LiveWallpaper` until I choose another, so that nothing changes for me today.
19. As a future UI, I want a Set Launch at login command, so that a checkbox controls whether the app starts at login.
20. As a user, I want Launch at login on by default for the existing install (the LaunchAgent behaviour), so that today's always-on behaviour is unchanged.
21. As a future UI, I want every command to return a clear result (done, or a typed reason it could not be done, e.g. folder unreadable), so that the UI can tell me what went wrong.

**What a future UI can show**

22. As a future UI, I want one snapshot of the app's state, so that a menu or window can be drawn from a single value.
23. As a future UI, I want the snapshot to name the Current video, its Poster and the reason it was chosen (first video, new video, Dwell, off-target, Mode change, visible fallback, Current video removed), so that I can see why this video is showing.
24. As a future UI, I want every Video in the Wallpaper folder listed with its catalogue status (settling, analysing, analysis failed, Excluded with its flash rate, overridden, eligible), so that I can see why a video isn't playing.
25. As a future UI, I want every eligible Video's Rotation status (Current, played this Pass, queued as new), so that I can see what's coming.
26. As a future UI, I want each Video's mean brightness and brightness rank, so that a list can be sorted or tinted by brightness.
27. As a future UI, I want Presence (Unseen, Veiled, Visible) in the snapshot, so that I can see whether a switch is waiting for me to look away.
28. As a future UI, I want Daylight, the Target brightness and the location source (fix, cache, time zone) in the snapshot, so that I can see why dynamic Mode picked what it did, without seeing my precise location.
29. As a future UI, I want the Playback state (playing, paused, Poster only) and any Recovery in progress (rebuilding in N seconds, resting on the Poster), so that I can see whether the wallpaper is healthy.
30. As a future UI, I want the Mode, the FlashOverride list, Enabled/Disabled, the Wallpaper folder and Launch at login in the snapshot, so that settings controls show their current values.
31. As a future UI, I want Dwell so far and the minimum for the next switch, so that I can show when the next change may happen.
32. As a future UI, I want to be told whenever the snapshot changes, so that the UI redraws without polling.
33. As a future UI, I want a stream of typed events (switch, Recovery, exclusion, override, Analysis done or failed, Presence change, Playback state change, Daylight source change, Enabled/Disabled), so that I can show recent activity.

**Domain model**

34. As a user, I want a renamed file treated as a new Video (re-analysed, played next), so that the behaviour matches what I see in Finder.
35. As a user, I want a file replaced under the same name treated as a new Version of the same Video (new Analysis and Poster, but its Pass history and FlashOverride kept), so that replacing a file doesn't lose my override.
36. As a developer, I want one Video type that identifies a Video by its file name and its Version by size and modification time, so that every context means the same thing by "video".
37. As a developer, I want Rotation to see only eligible Videos (name, Version, brightness), never flash rates or file handles, so that Rotation can't depend on screening details.
38. As a developer, I want Library to know nothing about Passes, Dwell or the Current video, so that the catalogue and the programme can change independently.
39. As a developer, I want the gate's internal states renamed to Playback state and "Mode" to mean only the user's Mode, so that code and glossary use one language.
40. As a developer, I want the Unseen/Veiled/Visible module named Presence, so that "visibility" stops meaning three things.

**Modules and boundaries**

41. As a developer, I want each context (Library, Rotation, Playback, Presence, Daylight, Desktop) to be a separate module whose domain code is internal, so that the compiler stops one context reaching into another.
42. As a developer, I want contexts never to reference one another, so that each can be read, tested and replaced on its own.
43. As a developer, I want one coordinator to route every event from one context to another context's commands, with the routing written out in one place, so that the order of reactions (e.g. Dwell hears of a lock before Presence reports it) is visible and tested.
44. As a developer, I want each context to have a pure, Foundation-only domain part and a separate adapter part, so that every decision stays testable without AppKit or AVFoundation.
45. As a developer, I want the Application layer to be Foundation-only and depend only on port protocols, so that it can be tested with fakes and later driven by a SwiftUI UI.
46. As a developer, I want the entry point (app delegate, notification observers, the 5 s tick, the composition of real adapters) in its own platform module, so that it's the only place that knows every concrete type.
47. As a developer, I want the shared 5 s tick to come from a clock port, so that tests can step time.

**Ports for the App Store phase**

48. As a developer, I want Wallpaper folder access behind a port (list, watch, read), so that a security-scoped bookmark adapter can replace the fixed path later.
49. As a developer, I want launch at login behind a port, so that an SMAppService adapter can replace the LaunchAgent later.
50. As a developer, I want reading, setting and restoring the desktop picture behind a port, so that sandbox-specific handling stays in one adapter.
51. As a developer, I want logging behind a port that consumes domain events, so that an `os.Logger` adapter can replace stderr later with no change to what is logged.
52. As a developer, I want location behind a port, so that the Daylight context doesn't import CoreLocation.
53. As a developer, I want settings persisted through one port as a typed Preferences value, so that no context reads `UserDefaults`.
54. As a developer, I want lock/unlock detection and the auto-appearance flag (both undocumented signals) behind ports with a documented public fallback, so that losing them later degrades gracefully rather than breaking.
55. As a developer, I want the time zone's reference coordinates behind a port, so that a bundled table can replace the system `zone.tab` later.
56. As a developer, I want playback, the system's power state and screen/session notifications behind ports, so that the Application layer can be tested end to end with fakes.

**Build, tests and concurrency**

57. As a developer, I want the app built as a SwiftPM package (one target per context, plus Application, Platform and an executable), driven by the existing `make` targets, so that boundaries are compiler-enforced and a thin Xcode project can wrap it for the App Store.
58. As a developer, I want the existing tests ported to swift-testing with the same assertions, so that nothing loses coverage in the move.
59. As a developer, I want Application-layer tests that drive the whole app through fake adapters (fake folder, player, clock, Presence signals, power, desktop picture, settings, location), so that scenarios like "the Current video is deleted mid-crossfade in Low Power Mode" are tests rather than manual checks.
60. As a developer, I want the analyser smoke test to keep running in `make build`, so that the flash screener is still checked end to end.
61. As a developer, I want the Application layer and adapters to be main-actor isolated and domain code pure, with Analysis off the main actor, so that a SwiftUI UI can bind to the snapshot safely.
62. As a developer, I want the package to build in Swift 6 language mode by the end of the phase, so that data races are caught by the compiler before a UI adds more concurrency.
63. As a developer, I want SwiftLint to cover every target and keep `--strict`, so that standards still hold across the new layout.
64. As a developer, I want the coding standards updated for contexts, the Application layer, ports and the SwiftPM build, so that future work follows the new shape.
65. As a developer, I want the debug-only overrides (folder, Dwell scale, clock, location) to keep working in debug builds only, so that manual checks remain possible.

## Implementation Decisions

**Baseline and sequencing**
- Ticket 10 (Daylight) is closed and its branch merged to `main` before this work branches. This phase starts from that `main`.
- Behaviour is preserved, except for the new commands and Disable/Quit restoring the desktop picture.
- The restructure lands in small steps, each of which leaves `make build` green and the installed app working:
  1. move to the SwiftPM package;
  2. introduce ports and adapters;
  3. extract contexts;
  4. add the Application layer, snapshot and events;
  5. move logging onto events;
  6. add the commands;
  7. switch to Swift 6 mode last.

**Bounded contexts.** Each context is one SwiftPM library target with an internal pure domain part and an adapter part.

| Context | Owns | Publishes | Accepts |
|---|---|---|---|
| **Library** | Wallpaper folder listing and watch, settle check, Analysis queue and cache, flash screening and verdicts, FlashOverride application, Posters (saving, export, pruning), launch underlay | Video catalogue (every Video with Version and catalogue status), eligible Videos; events: Video settled, Analysis done/failed, Excluded, overridden, eligible set changed | folder changed (from the coordinator, when the folder is chosen), overrides changed, Low Power Mode on/off, Poster for a Video |
| **Rotation** | Current video, Pass, new-video queue, Dwell, Mode filtering, Target brightness pick, switch decision | Rotation status per Video, Current video; events: switch decided (from, to, reason, fade, ΔL, deferred), waiting for Unseen, Mode in effect changed | eligible set, Presence, presence inputs that pause Dwell (lock, sleep, session), Mode, Daylight, Low Power Mode, tick |
| **Playback** | Shared player, windows and layers, Poster underlay, Crossfade, Recovery monitor and backoff, Playback state gate | Playback state, Recovery state, occlusion of every window; events: Recovery scheduled/resting, Playback state changed, video shown | play Video with fade, set Poster, Playback events (Low Power Mode, screens asleep, occlusion), wake/unlock verification, folder changed, show/hide (Enabled/Disabled), tick |
| **Presence** | Unseen/Veiled/Visible classification, coverage sampling for Veiled | Presence; event: Presence changed | presence inputs (occlusion, screens asleep, session inactive, locked), veil check request |
| **Daylight** | Sun position, Daylight curve, location resolution (fix, cache, time zone) | Daylight level and location source | location fix, time zone change, wake, activate (only when dynamic Mode wants it) |
| **Desktop** | Recording original desktop pictures, setting the Poster as the desktop picture, restore plan | events: originals recorded, Poster set, restored | set Poster, record originals, restore |

- Rotation has no adapters: it is pure domain plus a thin application-facing service.
- The windows belong to Playback. Occlusion is published as an input that the coordinator forwards to Presence and to the Playback gate.
- Daylight is its own context so weather (ticket 11, WeatherKit) can later adjust Daylight without touching Rotation.

**Video identity (shared kernel)**
- A small shared-kernel target, depended on by every context, holds only the types they must agree on:
  - **Video identity**: the file name;
  - **Version**: size plus modification time in milliseconds, as the Analysis cache key already uses;
  - **Eligible Video**: identity, Version, mean luminance;
  - the time and duration value types used across ports.
- Analysis and Poster are keyed by Version. Pass history, the new-video queue and FlashOverride are keyed by Video identity.
- A rename is a remove plus an add. A new Version of the same name keeps its Pass history and override, and triggers a new Analysis and Poster.
- Nothing else is shared. In particular, Rotation never sees flash rates.

**Application layer.** A Foundation-only, main-actor target that depends on each context's public interface and on port protocols, never on adapters.
- **Coordinator:** subscribes to each context's typed events and calls other contexts' commands. The routing is written out in one place (ADR 0002). It preserves today's ordering rules, including:
  - Dwell hears of lock, sleep or session changes before Presence reports them;
  - a folder change reaches Rotation before Playback rebuilds;
  - every video change sets the Poster under the video and as the desktop picture, guarded so a stale Poster is never applied;
  - a Presence change asks Rotation to decide at once.
- **Commands:** Set Mode, Set FlashOverride (one Video, on/off), Enable, Disable, Choose Wallpaper folder, Set Launch at login. Each returns success or a typed failure. Skip, Pin, manual Exclude and Re-analyse are deliberately absent, but nothing in the model blocks them: Rotation's switch decision has room for a user-requested switch.
- **Snapshot:** one immutable value made by joining the contexts' published state:
  - Current video with Poster and last switch reason;
  - every Video with its catalogue status and, if eligible, its Rotation status, brightness and rank;
  - Presence;
  - Daylight, Target brightness and location source (never coordinates);
  - Playback state and Recovery state;
  - Dwell so far and the next minimum;
  - Preferences;
  - Enabled/Disabled.

  A change notification fires whenever the snapshot changes.
- **Events:** one typed event enumeration covering every context's events, delivered to subscribers in order on the main actor.
- **Preferences:** one typed value holding Mode setting, FlashOverride names, Enabled, Wallpaper folder and Launch at login. It is loaded and saved through the settings port.
  - Mode and FlashOverride keep their existing storage keys, so `defaults write` still works.
  - An external change to the stored settings is picked up at decision time, as today.

**Enabled / Disabled**
- **Disable:**
  - Playback drops its player and closes its windows;
  - Rotation stops deciding and Dwell stops counting;
  - Desktop restores the originals using the existing restore plan (only screens showing our Poster are touched; fallback to another screen's original, then the system default);
  - Library keeps watching and analysing.
- **Enable:** Desktop records originals again (never overwriting a recorded entry for a screen that shows our Poster); Playback rebuilds; Rotation resumes; the Poster is set.
- **Quit:** application termination runs Disable's restore before exiting.
- The `--restore-wallpaper` flag stays, for `make uninstall`, and shares the same restore path.
- Enabled is persisted and defaults to Enabled.

**Ports.** Each is a protocol in the Application layer (or the owning context) with today's behaviour as its adapter.

| Port | Today's adapter | App Store adapter (later) |
|---|---|---|
| Wallpaper folder access (resolve, list with size/mtime, watch, keep access open) | fixed path or chosen path, `O_EVTONLY` dispatch source | security-scoped bookmark held for the app's lifetime |
| Launch at login | LaunchAgent plist installed by `make install`; the command reports state and can write/remove the user's plist | `SMAppService` |
| Desktop picture (read per screen, set, options) | `NSWorkspace` | same, sandbox-tested |
| Event log sink | timestamped stderr lines (existing format) | `os.Logger` with private fields |
| Settings store | `UserDefaults` standard domain | same, in container |
| Location (authorization, one-shot fix) | CoreLocation | same, with location entitlement |
| Time zone places | system `zone.tab` | bundled table |
| Lock/unlock signal | distributed screen lock/unlock notifications, with screen sleep/wake and session active/inactive as the documented fallback | same |
| Auto-appearance flag | global defaults key, falling back to "not auto" | same, or inferred from appearance changes |
| Clock and tick | system uptime and wall clock; 5 s repeating timer, tolerance 2 s | same |
| Power state | Low Power Mode notification | same |
| Screen and session events | NSWorkspace/NSApplication notifications | same |
| Player and windows | AVFoundation queue players, AppKit desktop-level windows | same |
| Analyser | AVAssetReader frame decoding | same, inside the folder's access scope |
| Window list (coverage) | `CGWindowListCopyWindowInfo` bounds/layer/alpha | same |

- App Store adapters are not built in this phase.
- Choosing a folder through the command stores a plain path in Preferences for now. The bookmark replaces it in the App Store phase, behind the same port.

**Logging**
- Each event has a single log rendering in a log-sink subscriber. Adapters no longer write log lines themselves, except adapter-only diagnostics (e.g. the wake-time player state report), which are emitted as diagnostic events.
- The existing causes and fields are kept, so the log reads as before. Precise coordinates are never logged.

**Build**
- The repository becomes a SwiftPM package. Targets:
  - shared kernel;
  - one per context;
  - Application;
  - Platform (app delegate, notification wiring, adapter composition);
  - the app executable;
  - the analyser smoke runner;
  - test targets.
- The Makefile keeps `build`, `test`, `smoke`, `lint`, `install`, `uninstall` and `debug`, implemented with `swift build`/`swift test`. It still assembles and signs the `.app` bundle exactly as today.
- Compiler-checked boundaries:
  - each context's domain types are `internal`;
  - each context exposes only its commands, published state, events and port protocols as `public`;
  - Platform is the only target that depends on every adapter.
- Debug overrides (folder, Dwell scale, clock, location) stay compiled in only for debug builds.
- Swift 6 language mode is enabled by the final step. Before that, strict concurrency checking runs as warnings.

**Concurrency**
- Domain code is pure, nonisolated and `Sendable` where it crosses actors.
- Application layer, contexts' services and AppKit/AVFoundation adapters are `@MainActor`.
- Analysis runs as an async task off the main actor and returns plain values. The existing `@unchecked Sendable` goes away.
- Callbacks from KVO, notifications and AV hop to the main actor at the adapter boundary.

**Standards and docs**
- `.claude/CODING_STANDARDS.md` is amended:
  - "no SwiftPM, no Xcode project" is replaced by the package layout (ADR 0001);
  - Code Organisation describes contexts, the shared kernel, the Application layer, ports and the coordinator (ADR 0002);
  - Testing describes swift-testing, Domain tests and Application tests with fakes;
  - the "~150 lines per type" and MARK conventions stay.
- README "How it works" and "What lives where" are updated to the new shape. The user-facing usage is unchanged.

## Testing Decisions

- **Two seams, highest first:**
  1. **The Application layer**: commands, snapshot and events, driven with fake adapters behind every port. This is the primary seam for new behaviour and cross-context scenarios.
  2. **Each context's pure domain functions and value types**: the existing seam. All existing Core tests keep their assertions and move to their context's test target.
- **Good tests** assert external behaviour: the snapshot, the events emitted, and the calls made on fake ports (e.g. "desktop picture set to the original on screen A"). They don't assert private state or the order of internal calls, except where the order is the contract (the coordinator's documented ordering rules).
- **Fakes:** in-memory folder (files with size/mtime, events on demand), fake player (scriptable ready/failed/stalled, reports position), steppable clock and tick, Presence signal source, power state, desktop picture store per screen, settings store, location provider, time zone places, deterministic RNG. They live in a test-support target.
- **Application scenarios to cover:**
  - launch with videos, none analysed, then Analysis completes;
  - a new Video plays next;
  - the Current video is deleted (with and without a crossfade in flight, and in Low Power Mode);
  - a Version is replaced under the same name: override kept, re-analysed;
  - a rename counts as a new Video;
  - lock, then unlock: Dwell pauses, an Unseen switch happens;
  - Veiled after coverage holds;
  - a Recovery backoff that rests, then resets on wake;
  - Low Power Mode on/off during a fade.
  - Each command, and its persistence across a simulated relaunch:
    - Set Mode;
    - Set FlashOverride (Excluded Video joins, then leaves);
    - Enable/Disable (restore and record behaviour, Analysis continues);
    - Quit restores;
    - Choose Wallpaper folder (switch, never black, unreadable folder fails with a typed reason);
    - Set Launch at login.
  - Snapshot correctness for every listed field.
  - The log sink renders the same lines as today for representative events.
- **Prior art:** the existing suites (Rotation, RotationDaylight, Recovery, Crossfade, PlaybackGate, VisibilityClassification, WallpaperFolder, AnalysisCache, Flash, Footprint, PosterFiles, PlayerStateReport, Daylight, Log), about 500 checks. They already follow "decision returned for given inputs" with injected clocks and RNGs. The analyser smoke test stays as the end-to-end check of the flash screener.
- **Gate:** `make build` runs lint, all tests, then the smoke test, then compiles; any failure stops the build and `make install`.
- **Manual checks** (unchanged from the previous spec, rerun once after the restructure):
  - rename the playing Video;
  - sleep and wake;
  - Ghostty in front;
  - Low Power Mode.

  Also:
  - Disable and Enable through a debug-only trigger: original desktop picture back, then the Poster again;
  - quit the app: original desktop picture back.

## Out of Scope

- Any UI: menu bar extra, settings window, Dock icon, SwiftUI views. The commands and snapshot are built for it; the views are the next phase.
- The App Store migration itself:
  - App Sandbox and entitlements;
  - security-scoped bookmarks;
  - `SMAppService`;
  - `os.Logger`;
  - the Xcode project wrapper, provisioning and App Store Connect;
  - a bundled time zone table;
  - testing `setDesktopImageURL` from a container on macOS 14/15.

  All of these are noted as the adapters each port will gain.
- New Rotation behaviour: Skip, Pin, manual Exclude, Re-analyse.
- Weather in Daylight (ticket 11).
- Any change to the Rotation, Recovery, Crossfade, Presence, flash or Daylight rules.
- Different videos per display; still images as wallpaper content.
- IPC or a separate UI process (the app stays one process; ADR 0002).

## Further Notes

- **App Store research summary** (2026-10-11):
  - A UI is mandatory for review: Guideline 4 requires an App Menu plus a Dock icon or menu bar extra, and 2.4.5(iii) requires login-item consent. So the next phase must ship at least Enable/Disable, Choose folder, Launch at login and Quit, which is why those commands exist now.
  - Sandboxed file access needs a user-chosen folder held by a bookmark for the app's lifetime; AVFoundation and folder watching work within it.
  - The LaunchAgent must become `SMAppService`.
  - Restore must happen in-app, because there is no uninstall hook.
  - The desktop-level window and the window list (bounds only) are fine.
  - The lock notifications and the auto-appearance key are undocumented, so they sit behind ports with fallbacks.
  - Signing and provisioning (and WeatherKit) favour a thin Xcode project over the Makefile, which is why the package exists.
- The previous spec (`.scratch/reliability-rotation/spec.md`) said the settings keys were designed for an external GUI/TUI. That design is superseded: the UI will be in-process and use the Application layer (ADR 0002). The keys remain only as storage.
- Commits omit the Co-Authored-By trailer (user preference).
