# 09: Rotation

**What to build:** Every eligible video takes turns. After 20 min of Dwell (awake, unlocked time), the next switch happens at the first Unseen or Veiled moment as a 5 s crossfade; if neither occurs, after 1 h of Dwell a 20 s crossfade happens while Visible. The next video is random among unplayed-this-Pass videos within ΔL ≤ 0.08 of the Current video; if none, the nearest unplayed one, allowed only while Unseen. `Mode` (all / light / dark / dynamic) is read live; default dynamic when appearance is Auto, else all; dynamic prefers the darker half (by median luminance) in Dark and brighter half in Light, acts as all with < 4 eligible videos, and replays a match when the half is exhausted. An appearance change waits for the next Unseen/Veiled moment. A newly added video plays next; deleting the Current video switches immediately. On each switch, the system desktop picture becomes the new video's Poster.

**Blocked by:** 06, 07, 08

**Status:** ready-for-agent

- [ ] Rotation pick, Mode filtering and Dwell accounting are pure core functions with tests (band, no repeat in a Pass, Unseen-only big jump, new video next, removal, <4 → all, half exhausted → replay, Dwell pauses while asleep/locked)
- [ ] Switch scheduler wires Dwell + Visibility + Library + Player; each switch logged with reason, from/to, ΔL and fade
- [ ] Appearance read via the app's effective appearance (observed), Auto detected read-only with fallback to all
- [ ] Desktop picture updated to the new Poster on switch
- [ ] README: Rotation behaviour, settings keys (`Mode`, `FlashOverride`) with `defaults` examples, "Design notes" with the research rationale
- [ ] Manual check with ≥ 3 test videos of differing brightness (generated in a temp folder) using shortened Dwell via a debug-only preference or test hook that is not user-facing
- [ ] `make build` green; rebase on main before review; `make install` after merge
