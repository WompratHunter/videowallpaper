# 03: Quiet when nobody's looking; settle before loading

**What to build:** The Live wallpaper stops costing anything when it can't be seen or macOS is saving power. In Low Power Mode the player is torn down and the Poster shows; it comes back when Low Power Mode ends. When every wallpaper window is fully occluded (opaque windows / full-screen app; translucent windows like Ghostty do not count) the shared player pauses and resumes when any window becomes visible again. Neither state is treated as "stuck" by Recovery. A video being copied into the Wallpaper folder is only loaded after its size is stable across two checks ~3 s apart.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] Low Power Mode on → Poster only, no player; off → player rebuilt; logged
- [ ] Pause when all wallpaper windows are occluded, resume when any is visible; occlusion changes logged (so lock-screen and Ghostty behaviour can be verified)
- [ ] Recovery's "intends to play" excludes Low Power Mode, occluded-pause and screens asleep (covered by tests)
- [ ] Settle check is a pure core function with tests; folder events are debounced and only settled files load
- [ ] Manual check: Ghostty maximized in front keeps the video playing; an opaque full-screen app pauses it (CPU drops in `top`)
- [ ] `make build` green; `make install`
