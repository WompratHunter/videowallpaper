# 08: Crossfade between videos

**What to build:** The Player can switch from the Current video to another with a smooth crossfade of a given duration (5 s or 20 s), on every display at once. A second shared player/layer pair loads the incoming video, waits until it is ready for display, animates opacity, then releases the outgoing player so two decoders only run during the fade. Recovery, the Poster underlay and pause/Low Power behaviour keep working during and after a fade. Until ticket 09, dropping a new newest video into the folder triggers a 5 s crossfade instead of a cut.

**Blocked by:** 05

**Status:** ready-for-agent

- [ ] Player interface accepts a fade duration; zero means cut
- [ ] Incoming layer waits for ready-for-display; no black or Poster flash between videos
- [ ] Outgoing player released after the fade (verify single decoder via CPU/logs)
- [ ] A fade interrupted by Recovery, Low Power Mode or occlusion pause ends in a sane state (tests for any pure state logic; manual check otherwise)
- [ ] Manual check: drop a second video in → 5 s crossfade on all displays
- [ ] `make build` green; rebase on main before review; `make install` after merge
