# 03: Presence context (parallel)

**What to build:** Unseen / Veiled / Visible lives in the Presence context, under that name (the code's "Visibility" becomes Presence, per the glossary). Lock/unlock detection goes behind a port whose adapter uses today's distributed screen lock/unlock notifications, with screens sleep/wake and session active/inactive as the documented public fallback; the window list goes behind a port. Presence publishes typed events (Presence changed, coverage sampled) that render as today's log lines, and its snapshot slice (current Presence). The `--check-veil` probe keeps working.

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

- [ ] Presence domain (classification, coverage, veil tracking) and adapters moved into the Presence target; nothing of Presence left in legacy targets
- [ ] Lock/unlock and window-list ports with today's adapters and fakes
- [ ] Presence events and snapshot slice; Presence log lines come from events and read as before
- [ ] Presence suites converted to native swift-testing in the Presence test target
- [ ] Application tests with fakes: lock then unlock gives Unseen then back; full coverage held for 30 s gives Veiled; translucent cover (occlusion false) stays Visible
- [ ] `make build` green
