# 10: Enable / Disable, and Quit restores

**What to build:** The Live wallpaper can be turned off and on as a domain state (see **Enabled** / **Disabled** in `CONTEXT.md`). Disable closes the windows, drops the player, stops Rotation decisions and Dwell, and restores the user's own desktop picture via Desktop's restore plan; Library keeps watching and analysing. Enable records originals again (never overwriting a recorded entry for a screen showing our Poster), rebuilds playback, resumes the Rotation and sets the Poster. Enabled is persisted in Preferences and defaults to Enabled. Quitting runs Disable's restore first: on application termination, and on SIGTERM (what `launchctl unload` sends), which is handled so the app terminates cleanly. With today's LaunchAgent `KeepAlive`, launchd relaunches a quit app; that's accepted until the App Store phase. A debug-build-only trigger (e.g. a signal) toggles Enable/Disable for the manual check.

**Blocked by:** 05, 07, 08

**Status:** ready-for-agent

**Read first:** `.scratch/domain-modules/spec.md` (the spec), `CONTEXT.md` (glossary: use its terms), `docs/adr/0001-swiftpm-targets-per-context.md`, `docs/adr/0002-contexts-meet-in-one-coordinator.md`, `.claude/CODING_STANDARDS.md`.

**Ground rules for every ticket in this set:**
- Behaviour visible to the user is unchanged unless this ticket says otherwise; the log keeps today's lines (same causes and fields).
- `make build` (lint `--strict`, all tests, smoke, compile) is green before you open the PR. Do not run `make install` or `make uninstall` (they restart the user's wallpaper and can block on a keychain prompt); manual checks that need them are listed for the user in the PR.
- Contexts never import one another; they meet only in the coordinator (ADR 0002). A context depends only on the shared kernel.
- Stay inside the files this ticket owns; tickets run in parallel. If you must touch a shared file (package manifest, another context's coordinator file), keep the edit to the minimum lines and say why in the PR.
- Commits omit the Co-Authored-By trailer (user preference).

## Acceptance criteria

- [ ] Enable and Disable commands with typed results, events and a snapshot field; persisted
- [ ] Quit and SIGTERM restore the original desktop picture before exit
- [ ] Application tests: Disable restores originals and stops decisions while Analysis continues; Enable after the user changed their picture records the new original; a relaunch while Disabled stays Disabled; Quit restores
- [ ] The PR lists manual checks for the user: debug-trigger Disable/Enable on the real desktop; `launchctl unload` restores
- [ ] `make build` green
