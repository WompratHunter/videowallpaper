# 02: Never black — shared player, Poster underlay, Recovery

**What to build:** The desktop can no longer go black. Every window shows the Poster beneath the video, so a dead player reveals the Poster. All displays are driven by one shared player (one decoder). When the player fails, stalls (playback time not advancing for 2 health ticks while it should be playing, 15 s grace after a rebuild), or is found not playing on wake/unlock, Recovery rebuilds the player and resumes the same video at the saved position (or 0). Retries back off 10 s → 1 min → 5 min, then rest on the Poster; the count resets on wake, unlock and folder change. Each Recovery is logged with its cause. Behaviour stays "newest video wins".

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] Poster layer under the video layer in every window; one decoded Poster image shared by all windows; window stays opaque
- [ ] One shared looping player feeds an `AVPlayerLayer` per window; windows ordered front without becoming key
- [ ] Recovery decision and backoff schedule are pure core functions with tests (stuck after 2 ticks, grace window, no-intent ticks ignored, failed → rebuild, backoff progression, reset on wake/unlock/folder change, rest on Poster after 3 failures)
- [ ] Health check runs on the existing single 5 s timer (with tolerance), comparing playback time between ticks — not trusting time-control status alone
- [ ] Item failure / failed-to-play-to-end notifications trigger Recovery
- [ ] Rebuild on wake/unlock only when not actually playing
- [ ] Resume at the saved position after rebuild
- [ ] Manual check: renaming the playing video mid-play logs a Recovery and shows the Poster, then the newest remaining video plays
- [ ] `make build` green; `make install` and the app is visibly playing
