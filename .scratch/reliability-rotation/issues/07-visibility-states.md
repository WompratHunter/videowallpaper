# 07: Visibility — Unseen, Veiled, Visible

**What to build:** The app always knows whether the Live wallpaper can be seen, and logs each change. Unseen = every wallpaper window occluded, screens asleep, or session inactive (notification-driven, no polling). Veiled = still visible, but on-screen normal-layer windows cover ≥ 95% of the screen continuously for 30 s (window-list bounds only, no Screen Recording permission; only evaluated when a caller asks, e.g. when a switch is due). Visible = otherwise. The Visibility module exposes the current state, a change callback, and the transition each state allows (5 s crossfade for Unseen/Veiled; Visible only via the 1 h, 20 s fallback). Session lock is verified to produce Unseen; if occlusion doesn't fire on lock, fall back to the screen lock/unlock distributed notifications.

**Blocked by:** 05

**Status:** done (installed ac6a107; lock/Ghostty/--check-veil checks pending user)

- [x] Classification and allowed-transition mapping are pure core functions with tests (inputs: occluded, screens asleep, session inactive, coverage fraction + duration)
- [x] Coverage computation (union of window bounds vs screen frame) is a pure function with tests
- [x] State changes logged; manual check: lock → Unseen, Ghostty maximized ≥ 30 s → Veiled, empty desktop → Visible
- [x] No new permission prompts
- [x] `make build` green; rebase on main before review; `make install` after merge

## Comments

- What was built:
  - Core (`VisibilityClassification.swift`):
    - `classifyVisibility`: Unseen wins over Veiled.
    - `VisibilityEvent` and `VisibilityInputs`.
    - `coverageFraction`: a union sweep of the window rects, clipped to the screen.
    - `leastCoverage`: counts normal-layer windows with alpha > 0.
    - `VeilTracker`: needs ≥ 95% coverage for 30 s, and restarts if two samples are more than 12 s apart.
    - `VisibilityTracker`: the step function. It returns the new state only when the state changed. Veiled lapses once samples stop.
    - `allowedTransition(for:)`: Unseen/Veiled → 5 s fade after 20 min of Dwell; Visible → 20 s fade after 1 h; only Unseen allows a big brightness jump.
    - All of these are tested in `VisibilityClassificationTests`.
  - App (`Visibility.swift`):
    - `state`, `onChange`, `apply(_:cause:)` and `checkVeil()`.
    - The window list is read only inside `checkVeil()`. It reads bounds and layer only, so no Screen Recording permission is needed.
    - An expiry runs 13 s after the last sample, so a Veiled that is no longer checked is logged back to Visible.
- Wiring in `main.swift`:
  - Occlusion, screens sleep/wake, session active, and unlock now also feed `visibility`.
  - New observers: `sessionDidResignActive` (fast user switch) and `com.apple.screenIsLocked`.
  - New `--check-veil` entry point.
  - `visibility.onChange` is not wired yet because nothing consumes it until 09. Each change is logged inside the module.
- Deviations and interpretations:
  - The lock fallback (`com.apple.screenIsLocked`/`Unlocked`) is wired from the start, because an agent can't lock the session to verify the occlusion path. It is harmless if occlusion also fires on lock. The log shows which input arrived first.
  - Veiled needs every screen ≥ 95% covered (the least-covered screen decides). This matches Unseen needing every window occluded. With 3 displays, Ghostty maximized on one display alone stays Visible.
  - Nothing in the app calls `checkVeil()` until 09's switch scheduler does, so `--check-veil` (a separate process: 9 samples 5 s apart, logged to stderr) is the way to check Veiled by hand now.
  - Session inactive (fast user switch) counts as Unseen per the spec. CONTEXT.md's Unseen definition only names "session locked".
- Manual checks after `make install` (log: `~/Library/Logs/videowallpaper.log`):
  - Lock (⌃⌘Q), wait, unlock. Expect `[lock] visibility=unseen …` or `[occlusion] … all-occluded=yes` followed by `visibility=unseen`. Note which came first; if no occlusion line appears around the lock, the lock notification is what carries Unseen. After unlock: `visibility=visible`.
  - Sleep the displays: `[screens-sleep] visibility=unseen …`; wake: `visibility=visible`.
  - Veiled: maximize Ghostty on every display (or test with only one display connected), then run `~/Applications/VideoWallpaper.app/Contents/MacOS/videowallpaper --check-veil`. Expect coverage ≥ 95% on every line, `[veil] visibility=veiled` at about 30 s after the first sample, and state=veiled after that. Coverage below 95% with the Dock visible means the Dock strip is uncovered.
  - Empty desktop: the same probe reports a low coverage and state=visible.
  - No permission prompt appears during any of these checks.
