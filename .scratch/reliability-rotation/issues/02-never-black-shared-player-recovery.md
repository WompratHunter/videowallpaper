# 02: Never black — shared player, Poster underlay, Recovery

**What to build:** The desktop can no longer go black. Every window shows the Poster beneath the video, so a dead player reveals the Poster. All displays are driven by one shared player (one decoder). When the player fails, stalls (playback time not advancing for 2 health ticks while it should be playing, 15 s grace after a rebuild), or is found not playing on wake/unlock, Recovery rebuilds the player and resumes the same video at the saved position (or 0). Retries back off 10 s → 1 min → 5 min, then rest on the Poster; the count resets on wake, unlock and folder change. Each Recovery is logged with its cause. Behaviour stays "newest video wins".

**Blocked by:** 01

**Status:** ready-for-agent

- [x] Poster layer under the video layer in every window; one decoded Poster image shared by all windows; window stays opaque
- [x] One shared looping player feeds an `AVPlayerLayer` per window; windows ordered front without becoming key
- [x] Recovery decision and backoff schedule are pure core functions with tests (stuck after 2 ticks, grace window, no-intent ticks ignored, failed → rebuild, backoff progression, reset on wake/unlock/folder change, rest on Poster after 3 failures)
- [x] Health check runs on the existing single 5 s timer (with tolerance), comparing playback time between ticks — not trusting time-control status alone
- [x] Item failure / failed-to-play-to-end notifications trigger Recovery
- [x] Rebuild on wake/unlock only when not actually playing
- [x] Resume at the saved position after rebuild
- [ ] Manual check: renaming the playing video mid-play logs a Recovery and shows the Poster, then the newest remaining video plays
- [ ] `make build` green; `make install` and the app is visibly playing

## Comments

- Layout: `Sources/Core/Recovery.swift` holds `RecoveryMonitor` (tick verdict, wake verdict, grace), `RecoveryBackoff` (10 s / 60 s / 300 s, then rest) and `resumePosition`, tested in `Tests/RecoveryTests.swift`. `Sources/App/Player.swift` is the shared player: it owns the queue player, the looper, the Poster and video layers, the health check, Recovery and the backoff. `WallpaperWindow` only hosts its layers. `make build` is green (70 checks).
- How Recovery runs: on a verdict the player is dropped straight away, so the Poster shows. It is rebuilt after the backoff delay, so the first rebuild comes 10 s after detection. The rebuild re-picks the newest video. For the same file it seeks to the saved position (taken on each healthy 5 s tick) before playing.
- Interpretations:
  - Resuming after screens-sleep also starts the 15 s grace, so a healthy player that is slow to restart is not torn down by the 1 s wake/unlock sample.
  - If the playing file disappears on a folder change, that logs `cause=file-missing` and starts Recovery.
  - Ending a rest on the Poster (on wake, unlock or folder change) logs `cause=retry-after-rest`.
  - Launch and `session-active` also run the playback verification, which is protected by the grace window.
- Known interaction left for ticket 04: `.poster.jpg` is still written into the Wallpaper folder. That fires the folder watcher, but folder events only reset the backoff when the set of videos (names and modification dates, hidden files excluded) changes, so Poster exports and `.DS_Store` writes are ignored (`Sources/Core/WallpaperFolder.swift`). At launch, the last `.poster.jpg` is loaded as the initial underlay. Before any Poster exists, the window background is black.
- Still to verify manually after `make install`:
  - The app is visibly playing on all displays, from one decoder: `top` shows a single process with low CPU.
  - Rename the playing video mid-play. The log should show `[recovery] cause=file-missing`, the Poster should show for about 10 s, then `rebuilding video=<newest>` and playback.
  - Delete the playing video: same as the rename check.
  - Run `pmset sleepnow`, then wake and unlock. The log should show the `screens-wake`/`wake`/`unlock` lines and a healthy player should not be rebuilt. If the player is dead, there should be a `not-playing-on-wake` Recovery line and playback should resume at about the same position.
  - Mission Control and Spaces: the window is not key and takes no focus, and it stays behind the desktop icons (`reassert` now uses `orderFront` within the desktop level, not `orderBack`).
  - A corrupt file as the newest video: three Recovery lines (10 s, 60 s, 300 s), then `resting on Poster`.
