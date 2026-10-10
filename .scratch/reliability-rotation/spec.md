# Spec: Never-black Live wallpaper + Rotation

Status: ready-for-agent

Sources: grilling session (2026-10-03), reviewed plan (Opus review pass), user answers A–H and T1–T3; Daylight grilling (2026-10-10), user answers Q1–Q14. Vocabulary per `CONTEXT.md`. Standards per `.claude/CODING_STANDARDS.md`.

## Problem Statement

I set up a video Live wallpaper on my MacBook (with two external displays). After the Mac woke from sleep, the Lock screen showed the Poster correctly, but once I unlocked, the desktop was solid black and stayed that way. The app was still running but its video had silently died, and nothing tried to bring it back. I also have no way to tell what went wrong, because the app logs nothing.

Beyond the bug, I want the wallpaper to be something I never touch: drop videos in a folder and it should look after itself. Changes of video should be smooth and never pull me out of focus (e.g. no dark-to-bright jumps while I'm working), unsafe flashing content shouldn't play, it should follow Light/Dark like Apple's dynamic wallpapers, and it should be cheap on battery even with high-resolution video across three displays.

## Solution

**Phase 1: never black.** The Live wallpaper always has the Poster drawn underneath the video, so a failed player shows the Poster, never black. A single shared player drives every display. The app detects a failed or stuck player and performs Recovery on its own, resuming where it left off, with sensible backoff. It pauses when nobody can see it (opaque windows covering everything, screens asleep) and in Low Power Mode, and logs every wake and Recovery so future problems are diagnosable. Dropped files are only loaded once fully copied. Uninstall leaves the system exactly as it was, including my original desktop picture. Behaviour is still "newest video wins" in this phase.

**Phase 2: Rotation.** Every eligible video in the Wallpaper folder takes turns. Each video gets a one-time Analysis (brightness, flash rate, Poster). Videos that flash more than 3 times a second are Excluded unless I list them in an override. Switches happen only after 20 minutes of Dwell, and preferably when the desktop is Unseen or Veiled, always as a smooth 5 s crossfade; if the desktop has been Visible the whole time, a slow 20 s crossfade to a similar-brightness video happens after 1 hour. The next video is chosen at random among those of similar brightness; large brightness jumps only happen while Unseen. With Auto appearance, Dark prefers darker videos and Light brighter ones. The lock screen always shows the Current video's Poster. A newly dropped video plays next.

**Phase 3: Daylight.** In `dynamic` Mode the wallpaper follows how bright it is outdoors where I am, not the Light/Dark appearance: dark videos at night, brighter ones through the day, drifting gradually across dusk and dawn. Daylight comes from the sun's position, calculated on the Mac from my location (Location Services if I allow it, otherwise my time zone), with no network calls by the app. If a clearly wrong video is showing (say, a bright one after I unlock at night), it is swapped at the next Unseen or Veiled moment without waiting for the usual 20 minutes. Weather (cloudy, stormy) is a later addition once WeatherKit is available.

## User Stories

1. As a user, I want the desktop to never be black after waking or unlocking, so that my Mac always looks intact.
2. As a user, I want the Poster to show whenever the video can't play, so that a failure looks like a still wallpaper rather than a broken screen.
3. As a user, I want a dead or stalled video to be detected automatically, so that I never have to restart anything.
4. As a user, I want Recovery to resume the same video at the same moment, so that the wallpaper doesn't visibly jump back to the start.
5. As a user, I want Recovery to retry with increasing delays and then rest on the Poster if a file is truly broken, so that a bad file doesn't burn CPU.
6. As a user, I want the retry count to reset after every wake, unlock or folder change, so that one bad night doesn't leave a good video stuck on the Poster.
7. As a user, I want Recovery on unlock only when the video isn't actually playing, so that a healthy video is never interrupted.
8. As a user, I want all three of my displays to show the same video from a single decoder, so that the app uses a third of the resources.
9. As a user, I want playback to pause while the desktop is completely covered by opaque windows, so that I save battery with no visible difference.
10. As a user with a translucent terminal (Ghostty, Terminal), I want the wallpaper to keep playing behind it, so that what I can see through the glass is still alive.
11. As a user on battery, I want playback to stop and the Poster to show in Low Power Mode, and resume when it ends, so that the wallpaper respects macOS's power saving.
12. As a user, I want a timestamped log line for every wake (with the player's state), Recovery, switch and exclusion, so that any future failure can be diagnosed.
13. As a user, I want a video I'm still copying into the folder to be ignored until the copy finishes, so that half-written files never get loaded.
14. As a user, I want no hidden files created in my Wallpaper folder, so that it contains only my videos.
15. As a user, I want uninstall to restore my original desktop picture and remove all app data and settings, so that nothing is left behind (except the app's Location Services entry, which macOS offers no command to remove; uninstall tells me how to remove it by hand).
16. As a user, I want everything to run as my own user with no special permissions, and at most one prompt (Location Services, only in `dynamic` Mode), so that my Mac's security and warranty are untouched.
17. As a user, I want every video in the folder to take turns, so that I get variety without doing anything.
18. As a user, I want a video to stay for at least 20 minutes of awake, unlocked time, so that the wallpaper feels settled rather than restless.
19. As a user, I want switches to happen when I can't see the desktop, or barely can, so that they don't break my concentration.
20. As a user who works fast, I want every switch to be a smooth 5-second crossfade, so that changes never look like a glitch.
21. As a user who stares at an uncovered desktop for a long time, I want a slow 20-second crossfade to a similar-brightness video after an hour, so that I still get variety without a jarring change.
22. As a user, I want each new pick to be random among videos of similar brightness, so that the order feels natural but never jumps from dark to bright while I'm looking.
23. As a user, I want large brightness changes allowed only while the desktop is Unseen, so that any big change happens when nobody's watching.
24. As a user, I want no video to repeat within a Pass, so that I see everything before anything repeats.
25. As a user, I want a video I just added to play at the next switch point, so that I see it soon after dropping it in.
26. As a user, I want a video I delete while it's playing to be replaced right away, so that the app never points at a missing file.
27. As a user with Auto appearance, I want Dark mode to prefer darker videos and Light mode brighter ones, so that the wallpaper follows the time of day like Apple's dynamic wallpapers.
28. As a user with a fixed Light or Dark appearance, I want all videos to play, so that the app doesn't guess at a preference I haven't expressed.
29. As a user, I want an appearance change to wait for the next Unseen or Veiled moment before switching, so that it never happens in front of me.
30. As a user, I want a `Mode` setting (all / light / dark / dynamic) stored in standard preferences and read live, so that a future GUI/TUI can control it without restarting the app.
31. As a user, I want videos flashing more than 3 times a second to be Excluded, so that unsafe content doesn't play on my desktop.
32. As a user, I want my soft-lightning rain video to keep playing, so that the safety check doesn't remove content that's actually fine.
33. As a user, I want a per-file `FlashOverride` list, so that I can allow a specific Excluded video (and later toggle it for someone else).
34. As a user, I want every Excluded video logged with its measured rate, so that I know why it isn't playing.
35. As a user, I want the README to describe the flash check honestly as an approximate screener (not a WCAG conformance test, no red-flash check), so that nobody relies on it more than they should.
36. As a user, I want each video's Analysis done once, in the background, and cached, so that adding videos costs almost nothing.
37. As a user, I want Analysis skipped in Low Power Mode, so that it never drains battery.
38. As a user, I want each video's Poster taken from a representative frame, so that the Lock screen doesn't show a dark intro frame.
39. As a user, I want the Lock screen and Mission Control to show the Current video's Poster, so that they match the wallpaper.
40. As a user, I want the cache pruned when I delete videos, so that app data doesn't grow forever.
41. As a user, I want `make build` to run lint and tests automatically, so that a broken build can never be installed.
42. As a user, I want the app reinstalled and restarted with `make install` after each merged change, so that I can see it working immediately.
43. As a user in `dynamic` Mode, I want the wallpaper to follow Daylight where I am (dark at night, bright at midday), so that it matches the light outside rather than a Light/Dark switch. (Supersedes 27 and 29.)
44. As a user, I want my exact location used if I allow it, and my time zone otherwise, so that it works well with permission and still works without it.
45. As a user, I want to be asked for location only once, and only when `dynamic` is in effect, so that the app never nags.
46. As a user, I want the location grant to survive `make install`, so that rebuilds don't re-prompt.
47. As a user, I want the wallpaper to drift gradually toward darker or brighter videos through dusk and dawn, so that the change is never visible as a jump.
48. As a user who unlocks at night to a bright video, I want it replaced at the next Unseen or Veiled moment without waiting out Dwell, so that a clear mismatch doesn't linger.
49. As a user, I want a video I just added to still play next, even at night, so that I see it soon after dropping it in.
50. As a user, I want my precise location never written to the log, so that the log is safe to share.
51. As a user, I want each switch logged with Daylight, the Target brightness and where my location came from, so that a surprising pick can be explained.

## Implementation Decisions

**Phasing**
- Phase 1 (never black) ships alone first and is tried briefly the same day. Phase 2 (Rotation) follows. Phase 1 keeps "newest video wins".

**Modules** (deep modules; small interfaces hiding most of the logic)
- **Core logic (Foundation-only):** every decision that can be expressed as a pure function or value type lives in one Foundation-only module, so it can be compiled into the test runner without AppKit/AVFoundation:
  - Recovery decision: given the playback time at consecutive ticks, the intent to play, the item's failed state and the time since the last rebuild, return whether to rebuild. Stuck means no time advance for 2 ticks while intending to play; there is a 15 s grace period after a rebuild. "Intending to play" excludes Low Power Mode, paused-because-Unseen and screens asleep.
  - Backoff schedule: 10 s, then 1 min, then 5 min, then rest on the Poster. Reset on wake, unlock or folder change.
  - Settle check: a file is ready when its size is unchanged across two checks about 3 s apart (playability is then confirmed by the player layer).
  - Phase 2: flash counting, luminance math (a 256-entry lookup table for sRGB→linear, BT.709 weights), Poster-frame choice, flash tiers with override, Rotation pick, Mode filtering, Dwell accounting, visibility classification and the allowed transition, and encoding/pruning the cache index.
- **Player:** owns one shared queue player + looper and an `AVPlayerLayer` plus a Poster layer per window. Interface roughly: show a video (at a position, with a fade duration), show the Poster, pause, resume, and a stuck/failed callback. Hides the looper, the health check on the shared tick, rebuild, seek-to-resume, crossfade via a second player/layer pair (wait for ready-for-display, animate opacity, then drop the old one), and the backoff. Windows only host layers. The window uses `orderFront` (never key).
- **Library (Phase 2):** owns the Wallpaper folder watch plus settle debounce, the Analysis queue (background, utility QoS, one at a time, skipped in Low Power Mode), the cache, exclusion and ordering. Interface roughly: eligible videos, the next pick after the current one (given mode, appearance and visibility), the Poster for a video, and a change callback.
- **Visibility (Phase 2):** classifies Unseen, Veiled or Visible.
  - **Unseen:** every wallpaper window's occlusion state lacks visible, screens are asleep, or the session is inactive. Driven by notifications with no polling. Translucent windows don't occlude, so Ghostty keeps the window Visible.
  - **Veiled:** still visible, but on-screen normal-layer windows cover at least 95% of the screen continuously for 30 s. Checked with the window list (bounds only, no Screen Recording permission), queried only when a switch is due.
  - **Visible:** otherwise.
- **App wiring:** the app delegate connects notifications (wake, sleep, session active/inactive, occlusion, power state, screen parameters, appearance via `effectiveAppearance`), the single 5 s timer (tolerance 2 s) and settings reads.
- **File layout:** Phase 1 may stay largely in one file plus the core-logic file. Phase 2 splits by module as types grow past ~150 lines (per the standards). The entry file becomes `main.swift` once there are multiple app files.

**Behavioural contracts**
- Poster: the Poster layer sits beneath the video layer in every window. One decoded image is shared by all windows. The window stays opaque.
- Pause while Unseen-by-occlusion (A): pause the shared player when all wallpaper windows are occluded; resume when any becomes visible. This relies on macOS not counting translucent windows as occluders. Verify with Ghostty and log occlusion changes.
- Logging: unbuffered stderr (the LaunchAgent already routes it to the log file); timestamp plus cause on every line. Every wake/unlock logs the player status, item status and error, time-control status, waiting reason and whether time advanced. No `print`, because lint bans it.
- Storage: Posters and the cache live in the app's Application Support folder, never in the Wallpaper folder. Any legacy `.poster.jpg` in the Wallpaper folder is removed.
- Desktop picture: on first run, record the user's original desktop picture per screen. Set the Poster as the desktop picture when the Current video changes; this affects the current Space only, which is accepted and documented. A `--restore-wallpaper` flag restores the original; `make uninstall` calls it, then removes the app support folder and the preferences domain.
- Transitions (B): every switch is a 5 s crossfade, whether Unseen or Veiled. Visible-only fallback: after 1 h of Dwell with no Unseen/Veiled opportunity, a 20 s crossfade to a video within the brightness band.
- Dwell (D): accumulates awake, unlocked time; minimum 20 min before any switch.
- Rotation pick: random among unplayed-this-Pass videos within ΔL ≤ 0.08 of the current one's mean luminance. If none, the nearest unplayed video, allowed only at an Unseen moment. A newly added video plays next (F). Removing the Current video triggers an immediate switch (the Poster covers the gap).
- Mode: `all`, `light`, `dark`, `dynamic`.
  - Default is `dynamic` when the global auto-appearance flag is set (an undocumented key, read-only, falling back to `all`), otherwise `all`.
  - `dynamic`: Dark prefers the darker half by median library luminance, Light the brighter half. With fewer than 4 eligible videos, it acts as `all`. If the matching half is exhausted, replay a match.
- Flash (C): an approximate screener for the WCAG 2.3.1 general flash threshold.
  - Method: decode every frame at reduced resolution, 12×12 grid, overlapping 2×2 neighbourhoods (≈2.8% of the screen) plus the full frame. A flash is a pair of opposing relative-luminance changes of at least 0.10 where the darker state is below 0.80. Count the maximum within any 1 s window.
  - Outcome: ≤3/s is eligible. Above 3/s is Excluded unless the file name is in `FlashOverride` (E: an array of file names).
- Settings: the app's own preferences domain (bundle id), keys `Mode` and `FlashOverride`, read at decision time.
- Daylight (Phase 3, supersedes the appearance rules of `dynamic` above):
  - Sun position: computed locally (NOAA solar algorithm) from coordinates and the current time; a pure core function. Handles polar day and night.
  - Daylight: 0 when the sun is below −6°, 1 above +25°, smoothstep between. Winter middays therefore still reach full day. Example: New York, 21 Dec: dark until ~06:45, full by ~10:15, falling from ~13:45, dark after ~16:58.
  - Target brightness: Daylight used directly as a percentile in the eligible videos' luminance ranking (0 = darkest, 1 = brightest).
  - Pick order in `dynamic`: (1) a newly added video plays next, regardless of target; (2) random among unplayed-this-Pass videos within ±0.15 of the target rank, and, while Visible, within ΔL ≤ 0.08 of the Current video; (3) if none while Visible, the in-band video nearest the target, so the wallpaper walks toward the target across dusk; (4) if still none, replay the played video nearest the target, never the Current one. With fewer than 4 eligible videos, `dynamic` acts as `all`.
  - Early switch: when the Current video's rank is more than 0.4 from the target, a switch is due regardless of Dwell, but only at an Unseen or Veiled moment.
  - Appearance: only chooses the default Mode (Auto → `dynamic`, else `all`). Appearance changes no longer trigger a switch.
  - Location source chain: one-shot CoreLocation fix at launch, on wake and on time-zone change → cached last fix (rounded to ~0.1°, stored in Application Support, used only if its time zone matches the current one) → coordinates for the current time-zone identifier from `/usr/share/zoneinfo/zone.tab`. Authorization is requested only when the effective Mode is `dynamic`, never again after a denial. No continuous monitoring. Precise coordinates are never logged.
  - Logging: every switch adds Daylight, Target brightness and location source (fix / cache / timezone); authorization changes and new fixes are logged (rounded coordinates only).
  - Weather is a later input to Daylight (ticket 11, WeatherKit); Daylight stays behind one interface so it can be added without touching the pick.
- Cache index: keyed by path + size + mtime; holds mean luminance, flash rate and Poster file name. Pruned on each folder scan.
- Analysis cost reference: a 20 s 4K60 clip takes ~3.6 s wall time and ~0.5 s CPU, once.

**Build**
- The Makefile builds all app Swift files. `build` depends on `lint` and `test`. `test` compiles the core-logic file(s) together with the test sources into a scratch build folder and runs them.
- SwiftLint's `included` list widens to cover all app and test Swift sources.
- `CODING_STANDARDS.md` gains a short Testing section describing the harness and what must be tested.
- Phase 3: the Makefile signs the `.app` with the user's "Apple Development" identity (falling back to ad-hoc if absent) so the Location Services grant survives rebuilds; it links CoreLocation. `Info.plist` gains `NSLocationUsageDescription` ("Matches your wallpaper's brightness to daylight where you are."). `make uninstall` prints how to remove the Location Services entry.

## Testing Decisions

- **Seam:** a single seam, the Foundation-only core-logic module. Tests exercise its public functions with plain values: time series, luminance arrays, file lists and an injected RNG. No AppKit, AVFoundation or timers inside tests.
- **Harness (T1a):** a plain `swiftc`-compiled test runner (`main.swift` with a tiny `check()` that exits non-zero on failure). No SwiftPM, no XCTest, so it works with or without full Xcode and takes about 0.5 s. Upgrade to SwiftPM + swift-testing only if the tests grow past a few dozen.
- **Good tests** assert external behaviour, i.e. the decision returned for given inputs: "stuck after 2 ticks without progress", "backoff resets on wake", "rain-like luminance yields ≤3 flashes/s", "no dark→bright pick while Visible". They do not assert internal state or call order.
- **Coverage (T2b):**
  - Phase 1: Recovery decision, backoff with reset, settle check.
  - Phase 2: flash counting (synthetic square waves at 2, 3, 4 and 6 Hz; slow drift not counted; small-region flashes caught), luminance LUT and mean, Poster-frame choice, tiers and override, Rotation pick (band, no repeat within a Pass, new video next, Unseen-only big jumps), Mode filtering (including <4 videos → all), Dwell, visibility classification and transitions, cache prune.
  - Phase 3: sun position vs NOAA reference sunrise/sunset for several cities and dates (±2 min), including polar day and night; Daylight curve; target → pick order (all four steps, new video beats target); early-switch threshold; location source chain including the same-time-zone check for the cache and `zone.tab` lookup.
  - One smoke test runs the real analyser on a generated 2 s clip with a known flash rate, so the accessibility screener is checked end to end.
- **Gate (T3a):** `make build` runs lint then tests; any failure stops the build and the install.
- **Manual checklist** (documented, run by agents where possible, with the user present for sleep):
  - Rename or delete the playing video: Recovery is logged and the Poster shows during the gap.
  - `pmset sleepnow`, then wake and unlock: the wake-state line is logged and playback recovers.
  - Idle cost via `top` in three states: Visible, covered by an opaque app, Low Power Mode.
  - Ghostty in front: the video keeps playing.
  - Phase 3: with a debug-only clock/location override (not user-facing), simulate dusk with ≥ 3 videos of differing brightness and confirm the walk toward darker videos and an early switch on lock/unlock; deny Location Services and confirm the time-zone fallback is logged.
- **Prior art:** none in the repo. The prototype analyser from the grilling session (handoff folder `flash.swift` / `flash12.swift`) is reference material for the flash algorithm, not code to copy as-is.

## Out of Scope

- A GUI or TUI for settings (the keys are designed for it later), including toggling `FlashOverride` per person.
- Weather conditions (cloud cover, storms) in Daylight: deferred to ticket 11 (WeatherKit, needs a paid Developer Program membership).
- The Mac's ambient light sensor (private API; measures the room, not the sky).
- Continuous location monitoring.
- A red-flash test or any certified photosensitivity assessment.
- Images (stills) as wallpaper content.
- Different videos per display.
- Updating the desktop picture on Spaces other than the current one.
- An ADR. The visibility-gated switching rationale goes in a README "Design notes" section instead.
- CI or GitHub Issues.

## Further Notes

- The root cause of the black screen is inferred, not proven: the process stayed alive, the window was on screen, CPU was 0%, and nothing was logged. The Poster underlay prevents black whatever the cause, and Phase 1 logging confirms it.
- Research basis for switching behaviour: abrupt luminance onsets capture attention (Yantis & Jonides 1984); gradual changes go unnoticed (Simons, Franconeri & Reimer 2000); interruptions at breakpoints cost less (Iqbal & Bailey 2008); WCAG 2.3.1 three-flash threshold.
- Machine context: Apple Silicon MacBook plus LG and HP 1080p displays, Auto appearance, Ghostty terminal, often on battery.
- Commits omit the Co-Authored-By trailer (user preference).
