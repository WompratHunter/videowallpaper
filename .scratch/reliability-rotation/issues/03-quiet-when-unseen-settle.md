# 03: Quiet when nobody's looking; settle before loading

**What to build:** The Live wallpaper stops costing anything when it can't be seen or macOS is saving power. In Low Power Mode the player is torn down and the Poster shows; it comes back when Low Power Mode ends. When every wallpaper window is fully occluded (opaque windows / full-screen app; translucent windows like Ghostty do not count) the shared player pauses and resumes when any window becomes visible again. Neither state is treated as "stuck" by Recovery. A video being copied into the Wallpaper folder is only loaded after its size is stable across two checks ~3 s apart.

**Blocked by:** 02

**Status:** ready-for-agent

- [x] Low Power Mode on → Poster only, no player; off → player rebuilt; logged
- [x] Pause when all wallpaper windows are occluded, resume when any is visible; occlusion changes logged (so lock-screen and Ghostty behaviour can be verified)
- [x] Recovery's "intends to play" excludes Low Power Mode, occluded-pause and screens asleep (covered by tests)
- [x] Settle check is a pure core function with tests; folder events are debounced and only settled files load
- [ ] Manual check: Ghostty maximized in front keeps the video playing; an opaque full-screen app pauses it (CPU drops in `top`)
- [ ] `make build` green; `make install` (build green with 179 checks; install left to the orchestrator)

## Comments

- Layout:
  - `Sources/Core/PlaybackGate.swift` is the combined intent/pause state machine. It tracks Low Power Mode, screens asleep and every window occluded, and gives a mode of `playing`, `paused` or `posterOnly`. For each event it returns `pause`, `resume`, `tearDown`, `rebuild` or `none`. Its `isIntendingToPlay` is what Recovery receives, and its `isPowerSaving` gates `rebuildPlan` (`.holdForPower`) and `folderChangeAction` (`.holdForPower`). Leaving Low Power Mode rebuilds, unless the backoff is exhausted (resting).
  - `Sources/Core/WallpaperFolder.swift` holds the settle check. `settledVideos` keeps a file only when its non-zero size is unchanged between two snapshots. `FolderSettler` returns a `SettleOutcome` and re-checks every 3 s while any file is in flux, because the directory watch does not fire while a file grows. A stable empty file is not polled. The settle wait replaces the old 2 s debounce: `rebuildSoon` is now `rebuildNow`.
  - `RecoveryBackoff.reset(on:isPowerSaving:)` decides whether a rest ends with a retry. It does not retry in Low Power Mode.
  - Tests: `Tests/PlaybackGateTests.swift` (including `RecoveryMonitor` driven from the gate, for each pause reason), `Tests/WallpaperFolderTests.swift` and `Tests/RecoveryTests.swift`.
- Interpretations:
  - Videos present at launch play at once. The launch snapshot is the baseline for the first check 3 s later, so a copy still running at launch is dropped then, and loaded once it settles.
  - Entering Low Power Mode cancels a pending Recovery rebuild, and leaving it rebuilds straight away (the backoff count is kept). This clearing of Recovery state is applied in `Player.apply`; the rule is documented on `PlaybackGateAction.tearDown` but is not returned as state from Core.
  - "Unseen" because the session is inactive or locked is left to ticket 07. This ticket covers occlusion and screens asleep only.
- Log lines: `[occlusion] windows=N all-occluded=yes|no` on window build, and `[occlusion] screen=N visible=yes|no all-occluded=yes|no` on each change. `[power] low-power=on|off`. `[playback] event=… action=pause|resume|tearDown|rebuild mode=…` when the player is affected. `[folder-change] settled videos=N`.
- Manual checks after `make install`:
  - Ghostty maximized in front of the desktop on every display: the log shows `visible=yes` and the video keeps playing.
  - An opaque full-screen app on every display: `all-occluded=yes`, then `action=pause`, and CPU drops in `top`. Leaving it shows `action=resume` and playback continues from the same frame.
  - Launch occlusion: right after launch, check that `[occlusion] windows=3 all-occluded=no` is logged and the video plays. If it logs `yes` at launch (state not computed yet), it should resume on the first `screen=N visible=yes` line. If it stays paused, that is a bug.
  - Lock screen: lock and watch the `occlusion` and `screens-sleep` lines, then unlock and check there is no spurious Recovery.
  - Low Power Mode (System Settings → Battery): turning it on logs `low-power=on` and `action=tearDown`, the Poster shows and CPU is about 0. Turning it off logs `action=rebuild` and `rebuilding video=… at=<saved position>`.
  - Copy a large video into the folder slowly (e.g. from a network share). Nothing should load until about 3 s after the copy ends. Then `settled videos=N` is logged and the new video plays.
