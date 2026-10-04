# 09: Rotation

**What to build:** Every eligible video takes turns. After 20 min of Dwell (awake, unlocked time), the next switch happens at the first Unseen or Veiled moment as a 5 s crossfade; if neither occurs, after 1 h of Dwell a 20 s crossfade happens while Visible. The next video is random among unplayed-this-Pass videos within ΔL ≤ 0.08 of the Current video; if none, the nearest unplayed one, allowed only while Unseen. `Mode` (all / light / dark / dynamic) is read live; default dynamic when appearance is Auto, else all; dynamic prefers the darker half (by median luminance) in Dark and brighter half in Light, acts as all with < 4 eligible videos, and replays a match when the half is exhausted. An appearance change waits for the next Unseen/Veiled moment. A newly added video plays next; deleting the Current video switches immediately. On each switch, the system desktop picture becomes the new video's Poster.

**Blocked by:** 06, 07, 08

**Status:** done (installed 2d23f8f: launch logs mode=dynamic, first-video maomao in the Light half; debug-Dwell run left to the user)

- [x] Rotation pick, Mode filtering and Dwell accounting are pure core functions with tests (band, no repeat in a Pass, Unseen-only big jump, new video next, removal, <4 → all, half exhausted → replay, Dwell pauses while asleep/locked)
- [x] Switch scheduler wires Dwell + Visibility + Library + Player; each switch logged with reason, from/to, ΔL and fade
- [x] Appearance read via the app's effective appearance (observed), Auto detected read-only with fallback to all
- [x] Desktop picture updated to the new Poster on switch
- [x] README: Rotation behaviour, settings keys (`Mode`, `FlashOverride`) with `defaults` examples, "Design notes" with the research rationale
- [ ] Manual check with ≥ 3 test videos of differing brightness (generated in a temp folder) using shortened Dwell via a debug-only preference or test hook that is not user-facing (mechanism built: `make debug`, see Comments; the run is the user's step, since it sets the desktop picture)
- [x] `make build` green; rebased; installed 2d23f8f

## Comments

- Built:
  - Core `Rotation.swift`:
    - `rotationMode(setting:isAutoAppearance:)`: a missing or unknown `Mode` gives `dynamic` under Auto, else `all`.
    - `modeCandidates`: the darker or brighter half by median luminance. A video at the median is in both halves. `dynamic` with fewer than 4 videos acts as `all`.
    - `pickNext`: random among unplayed-this-Pass videos within ΔL ≤ 0.08, else the nearest unplayed one only if a big jump is allowed. A new Pass starts once the candidates are exhausted, so a half that has all played replays from that half.
    - `Dwell`: counts only while at the desk, and each step is capped at 30 s so an unheard sleep doesn't count.
    - `RotationState.decide(_:using:)`: the whole state machine. It covers the first video, the removed Current video, a new video next, Mode/appearance off-half (switches at Unseen/Veiled without Dwell), Dwell (Unseen/Veiled after 20 min, 5 s) and the Visible fallback (1 h, 20 s, band only). It returns `.switchTo`, `.stay` or `.waitingForUnseen`. A switch in Low Power Mode is `isDeferred`.
  - Tests in `RotationTests`: seeded SplitMix64 RNG and explicit clock, on the user's 4 measured luminances.
  - App `RotationScheduler.swift`: gathers the inputs, samples Veiled (`checkVeil`) only when `isSwitchPointNear`, observes `NSApp.effectiveAppearance` by KVO and logs. The tick and Visibility changes call `player.play(_:fade:)`. Folder changes and rebuilds read `rotation.video`.
- Behaviour with the user's videos (capybara 0.299, ff7 0.037, lucyna 0.161, maomao 0.177):
  - Only lucyna↔maomao (ΔL 0.016) can switch while Veiled or Visible. Reaching or leaving ff7 or capybara needs Unseen (lock, displays asleep, or fully covered by opaque windows).
  - The median is 0.169. `dynamic` Dark = {ff7, lucyna} and Light = {maomao, capybara}. Within each half the pair is > 0.08 apart, so every in-half switch needs Unseen. A Dark→Light flip while on lucyna goes to maomao at the next Veiled moment.
- Wiring (`main.swift`):
  - `rotation` is created at launch with the folder's present names (so they don't count as "new").
  - `rotation.start()` runs after `library.start()`. The launch underlay uses `rotation.video`.
  - `player.videoProvider` refreshes and returns `rotation.video`.
  - `library.onChange` now takes no argument: refresh, then `player.folderChanged(toPlay: rotation.video, fade:)`. This replaces 08's interim newest-video crossfade.
  - `connectRotation()` sets inputs, `Mode`, the auto-appearance flag and `onSwitch`.
  - `visibility.onChange` now calls `rotation.evaluate`. It was previously unwired.
  - Sleep, lock and session events go through `noteVisibility` to both Rotation (Dwell) and Visibility.
  - The tick calls `rotation.evaluate(cause: "tick")`.
- Desktop picture: unchanged mechanism. Every switch ends in `player.onVideoChange` → `showPoster` → `DesktopPictures.setPoster`, after a cut or once a crossfade promotes.
- Other changes: `Library.videoToPlay()` and Core `newestVideo` were removed. `folderChanged(newest:)`, `folderChangeAction(newest:)` and `rebuildPlan(newest:)` were renamed `toPlay:`. The standards list the Rotation module.
- Deviations and interpretations:
  - A new video plays next, ahead of the random pick, regardless of Mode. It still obeys the brightness rule, so a far-off new video waits for Unseen and holds other switches until then.
  - Review: an off-Mode new video keeps its full Dwell (the Mode-change shortcut skips it), and a lone video doesn't ask for the window list. The tick reads the Library's cached eligible list, so a deletion switches after the settle check (about 3 s).
  - Videos present at launch but analysed later join without counting as new. A deleted and re-added name counts as new.
  - Dwell also pauses while the displays sleep (not just while locked) and during fast user switching. Opaque windows don't pause it.
  - An off-Mode Current video (appearance flip or `Mode` edit) switches at the next Unseen/Veiled moment without waiting for Dwell.
  - Explicit `light`/`dark` halve at any count. Only `dynamic` has the < 4 → all rule.
  - Low Power Mode: no Dwell switches. A removal is chosen but deferred, and plays when the rebuild after Low Power Mode runs.
  - Rotation state (Pass, Dwell) is in memory. A relaunch starts a new Pass with a random first video.
  - A crossfade whose incoming video fails (abandoned in 08) leaves the Rotation's Current video ahead of the player. Accepted: an analysed file failing to load is unlikely, and the next rebuild plays the Rotation's pick.
- Debug Dwell (not user-facing): `make debug` builds `.build/videowallpaper-debug` with `-D DEBUG`. Only that binary honours two environment variables:
  - `VIDEOWALLPAPER_DWELL_SCALE`, e.g. `0.01`: 20 min becomes 12 s and 1 h becomes 36 s. Veiled's 30 s is not scaled.
  - `VIDEOWALLPAPER_FOLDER`: the Wallpaper folder. Its cache and Posters go in `<folder>-support`, so the installed app's are never pruned.
  The release build (`make build`/`install`) compiles both out.
- Manual checks after `make install` (log: `~/Library/Logs/videowallpaper.log`):
  - Launch logs `[rotation] mode=dynamic setting=none auto-appearance=yes` (with Auto), then `switch reason=first-video …`.
  - Lock after ≥ 20 min of use: `switch reason=dwell on=visibility … visibility=unseen fade=5s`. The Lock screen and desktop picture show the new Poster.
  - On lucyna or maomao, maximise Ghostty on every display for > 30 s after 20 min: a Veiled switch to the other one (ΔL=0.016). On ff7 or capybara, the log shows `waiting for Unseen` once instead.
  - Leave the desktop uncovered for 1 h on lucyna: `reason=visible-fallback fade=20s` to maomao.
  - Drop in a new video: it is analysed, then at the next switch point `reason=new-video`.
  - Delete the playing video: `reason=current-removed` at once, a `file-missing` Recovery, the Poster in the gap, then the new video.
  - Flip Light/Dark in System Settings: `appearance=dark` is logged. If the Current video is in the other half it switches (`reason=mode-change`) at the next lock or Veiled moment, not straight away.
  - `defaults write com.evanscott.videowallpaper Mode -string all`: the next tick logs `mode=all`.
- Manual check with shortened Dwell (unload the agent first so two instances don't fight; it sets the desktop picture):
  1. `launchctl unload ~/Library/LaunchAgents/com.videowallpaper.plist`
  2. Generate ≥ 3 clips of differing brightness in a temp folder. For example, for each luminance value `L` in `0.1`, `0.15` and `0.6`, run `ffmpeg -f lavfi -i color=gray:s=640x360:d=10 -vf "lutyuv=y=val*<L>/0.5" /tmp/vw/<L>.mp4`, or use any three videos.
  3. `make debug && VIDEOWALLPAPER_FOLDER=/tmp/vw VIDEOWALLPAPER_DWELL_SCALE=0.01 .build/videowallpaper-debug`
  4. Expect: after about 12 s, locking switches; covering with opaque windows switches; Visible switches after about 36 s only between the close pair; the far clip only while Unseen.
  5. Quit with ⌃C, then `launchctl load ~/Library/LaunchAgents/com.videowallpaper.plist`. The next switch restores the real Poster.
