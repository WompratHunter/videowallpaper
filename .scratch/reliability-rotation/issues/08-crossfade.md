# 08: Crossfade between videos

**What to build:** The Player can switch from the Current video to another with a smooth crossfade of a given duration (5 s or 20 s), on every display at once. A second shared player/layer pair loads the incoming video, waits until it is ready for display, animates opacity, then releases the outgoing player so two decoders only run during the fade. Recovery, the Poster underlay and pause/Low Power behaviour keep working during and after a fade. Until ticket 09, dropping a new newest video into the folder triggers a 5 s crossfade instead of a cut.

**Blocked by:** 05

**Status:** done (manual checks pending install)

- [x] Player interface accepts a fade duration; zero means cut
- [x] Incoming layer waits for ready-for-display; no black or Poster flash between videos
- [x] Outgoing player released after the fade (verify single decoder via CPU/logs; CPU check is manual, below)
- [x] A fade interrupted by Recovery, Low Power Mode or occlusion pause ends in a sane state (tests for any pure state logic; manual check otherwise)
- [ ] Manual check: drop a second video in → 5 s crossfade on all displays
- [ ] `make build` green; rebase on main before review; `make install` after merge (build green and rebased; install pending merge)

## Comments

- Layout:
  - `Sources/Core/Crossfade.swift` is the fade state machine, tested in `Tests/CrossfadeTests.swift` (registered in `Tests/main.swift`). Each event returns a list of `CrossfadeAction`s: `cut`, `load`, `animate`, `promote`, `dropIncoming` and `abandon`. The events are `request`, `incomingReady`, `animationFinished`, `incomingFailed`, `pause`, `interrupt` and `tick`. Ids make stale readiness and finish callbacks harmless.
  - `Sources/App/PlayerCrossfader.swift` owns the incoming `LoopingPlayer` and applies the actions. `LoopingPlayer` (player plus looper, muted, no display-sleep prevention) is now also what `Player` holds.
  - `Sources/App/PlayerLayers.swift` has two video slots per window above the Poster. The incoming slot sits above the active one at opacity 0, is observed for `isReadyForDisplay` on every window, and fades in with an ease-in-out opacity animation. Implicit animations are disabled.
  - `Player.play(_:fade:)` is the interface (0 = cut). `folderChanged(newest:fade:)` passes the fade to a `switchTo`.
- Decisions and interpretations:
  - A fade only runs while the gate is `playing`. A paused or torn-down player gets a cut, because nobody sees it and a fade would only cost a second decoder.
  - Occlusion or screens-asleep pause during a fade completes it at once: the incoming video is promoted and paused, and the outgoing one is released.
  - Recovery, Low Power Mode and any cut tear both players down, so the incoming player is dropped. The rebuild re-picks the newest video as before.
  - If the incoming video fails, or isn't ready for display within 15 s, it is abandoned and the healthy outgoing video keeps playing (logged). It is not cut to or recovered, so a switch can never drop the wallpaper to the Poster.
  - A different target requested mid-fade is queued and fades in after the current fade finishes. While still loading, the incoming video is replaced instead. A fade whose finish never arrives is completed by the tick 15 s after its end.
  - A fade always starts the incoming video at 0. Resuming at a saved position stays a Recovery rebuild, which cuts.
  - The 20 s duration is just a `fade:` value. Rotation (09) owns that choice, so no 20 s constant was added here.
  - Known edge, accepted: a display connected mid-fade shows the incoming video at full opacity on that screen immediately.
- Probe: a throwaway program confirmed that an opacity-0 `AVPlayerLayer` in an on-screen window still becomes ready for display (about 0.09 s).
- Wiring: `main.swift` `library.onChange` now calls `folderChanged(newest:fade: Crossfade.quickDuration)`. Nothing else changed.
- Log lines: `[crossfade] loading video=…`, `fading video=… over=5s`, `done video=…`, `dropped incoming video=…`, `abandoned video=…`, `cut video=…`.
- Manual checks after `make install`:
  - Drop a second (newer) video into the Wallpaper folder. After the settle check, the log shows `loading`, `fading … over=5s` and `done`, and every display crossfades smoothly over about 5 s with no black or Poster flash. The Poster and desktop picture then update to the new video.
  - Single decoder: `top -pid $(pgrep videowallpaper)`. CPU rises during the fade and drops back to the one-video level after `done`.
  - Cover every display with an opaque full-screen app during a fade. `action=pause` is logged, then `done` straight away. Leaving the app shows the new video, resumed.
  - Turn on Low Power Mode during a fade. `action=tearDown` and `dropped incoming` are logged and the Poster shows. Turning it off rebuilds the new video.
  - Drop a corrupt `.mp4` as the newest video. `abandoned video=…` is logged and the current video keeps playing.
  - Delete the playing video mid-fade. `file-missing` Recovery is logged, the incoming player is dropped and the rebuild plays the newest video.
