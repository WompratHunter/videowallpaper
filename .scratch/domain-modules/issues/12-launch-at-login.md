# 12: Set Launch at login (parallel)

**What to build:** A future UI can turn launch at login on and off. A launch-at-login port reports and sets the state; today's adapter manages the user's LaunchAgent plist (the same content `make install` writes): on writes it, off removes the file so the app doesn't start at the next login. It never calls `launchctl` (unloading would kill the running app). The state is in the snapshot and reported by an event. The App Store phase swaps in `SMAppService` behind the same port.

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

- [ ] Launch-at-login port with a LaunchAgent-plist adapter and a fake; command with typed result, event and snapshot field
- [ ] Plist content identical to what `make install` writes (share the template rather than duplicate it)
- [ ] Application tests for on, off and status; the adapter tested against a temporary directory
- [ ] `make build` green
