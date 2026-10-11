# 08: Rotation context (parallel)

**What to build:** The Rotation (Current video, Pass, new-video queue, Dwell, Mode filtering, Target brightness pick, switch decision) lives in the Rotation context, which has no OS adapters except the auto-appearance flag, which goes behind a port (global key, falling back to "not auto"). Rotation takes eligible Videos, Presence, away-from-desk, Mode, Daylight and Low Power Mode as inputs from the coordinator. It publishes per-Video Rotation status (Current, played this Pass, queued as new), Dwell so far and the next minimum, and the last switch reason in its snapshot slice, plus events (switch decided, waiting for Unseen, Mode in effect) rendering today's log lines.

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

- [ ] Rotation domain and scheduler moved into the Rotation target; no AppKit in it (appearance comes through the port)
- [ ] Rotation status, Dwell and last switch in the snapshot; Rotation events; log lines unchanged
- [ ] Rotation suites (Rotation, RotationDaylight) converted to native swift-testing
- [ ] Application tests: a newly added Video plays at the next allowed switch; a switch waits for Dwell then happens at the first Unseen moment with a 5 s crossfade; a visible-only hour gives the 20 s fallback; a deleted Current video is replaced at once
- [ ] `make build` green
