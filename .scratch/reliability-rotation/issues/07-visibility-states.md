# 07: Visibility — Unseen, Veiled, Visible

**What to build:** The app always knows whether the Live wallpaper can be seen, and logs each change. Unseen = every wallpaper window occluded, screens asleep, or session inactive (notification-driven, no polling). Veiled = still visible, but on-screen normal-layer windows cover ≥ 95% of the screen continuously for 30 s (window-list bounds only, no Screen Recording permission; only evaluated when a caller asks, e.g. when a switch is due). Visible = otherwise. The Visibility module exposes the current state, a change callback, and the transition each state allows (5 s crossfade for Unseen/Veiled; Visible only via the 1 h, 20 s fallback). Session lock is verified to produce Unseen; if occlusion doesn't fire on lock, fall back to the screen lock/unlock distributed notifications.

**Blocked by:** 05

**Status:** ready-for-agent

- [ ] Classification and allowed-transition mapping are pure core functions with tests (inputs: occluded, screens asleep, session inactive, coverage fraction + duration)
- [ ] Coverage computation (union of window bounds vs screen frame) is a pure function with tests
- [ ] State changes logged; manual check: lock → Unseen, Ghostty maximized ≥ 30 s → Veiled, empty desktop → Visible
- [ ] No new permission prompts
- [ ] `make build` green; rebase on main before review; `make install` after merge
