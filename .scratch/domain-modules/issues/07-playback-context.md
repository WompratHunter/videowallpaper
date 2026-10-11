# 07: Playback context (parallel)

**What to build:** The shared player, windows and layers, Poster underlay, Crossfade, Recovery and the gate live in the Playback context. The gate's states are renamed to Playback state (playing, paused, Poster only), per the glossary. The player, the windows (including occlusion), power state and screen/session notifications go behind ports with today's AVFoundation/AppKit adapters. Playback publishes Playback state and Recovery state (rebuilding in N s, resting on the Poster) in its snapshot slice, and events (Recovery scheduled/resting/rebuilt, Playback state changed, video shown, crossfade steps, the wake-time player state report) rendering today's log lines.

**Blocked by:** 02

**Status:** ready-for-agent

**Read first:** `.scratch/domain-modules/spec.md` (the spec), `CONTEXT.md` (glossary: use its terms), `docs/adr/0001-swiftpm-targets-per-context.md`, `docs/adr/0002-contexts-meet-in-one-coordinator.md`, `.claude/CODING_STANDARDS.md`.

**Ground rules for every ticket in this set:**
- Behaviour visible to the user is unchanged unless this ticket says otherwise; the log keeps today's lines (same causes and fields).
- `make build` (lint `--strict`, all tests, smoke, compile) is green before you open the PR. Do not run `make install` or `make uninstall` (they restart the user's wallpaper and can block on a keychain prompt); manual checks that need them are listed for the user in the PR.
- Contexts never import one another; they meet only in the coordinator (ADR 0002). A context depends only on the shared kernel.
- Stay inside the files this ticket owns; tickets run in parallel. If you must touch a shared file (package manifest, another context's coordinator file), keep the edit to the minimum lines and say why in the PR.
- Commits omit the Co-Authored-By trailer (user preference).

## Acceptance criteria

- [ ] Playback domain and adapters moved into the Playback target; the gate's mode renamed to Playback state
- [ ] Player/windows, power and screen/session ports with today's adapters; a scriptable fake player (ready, failed, stalled, position)
- [ ] Playback events and snapshot slice; log lines unchanged
- [ ] Playback suites converted to native swift-testing
- [ ] Application tests: Current video deleted mid-crossfade in Low Power Mode ends on the Poster, then plays the replacement when Low Power Mode ends; a stalled player recovers with backoff and rests after the last attempt, then retries on wake; all windows occluded pauses and is not counted as stuck
- [ ] `make build` green
