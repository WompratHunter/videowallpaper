# 05: Desktop context (parallel)

**What to build:** Recording the user's original desktop pictures, setting the Poster as the desktop picture and the restore plan live in the Desktop context, behind a desktop-picture port (read per screen with options, set per screen) whose adapter is today's `NSWorkspace` code. `--restore-wallpaper` (used by `make uninstall`) goes through the Desktop context. Desktop publishes events (originals recorded, Poster set, restored, failures) that render as today's log lines.

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

- [ ] Desktop domain (record, restore plan) and adapter moved into the Desktop target
- [ ] Desktop-picture port with today's adapter and an in-memory per-screen fake
- [ ] `--restore-wallpaper` still restores and exits with the same status codes
- [ ] Desktop suites converted to native swift-testing
- [ ] Application tests: the first Poster records originals first; a screen already showing our Poster isn't recorded; restore touches only screens showing our Poster and falls back as specified
- [ ] `make build` green
