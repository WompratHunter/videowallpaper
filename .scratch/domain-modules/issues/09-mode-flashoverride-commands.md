# 09: Set Mode and Set FlashOverride commands

**What to build:** A future UI can change the Mode and a Video's FlashOverride through Application-layer commands instead of `defaults write`. Each command validates, saves through Preferences (same storage keys, so `defaults` still works and an external edit is still picked up at decision time), returns success or a typed failure, emits an event and updates the snapshot. Setting an override on an Excluded Video makes it eligible at once (it can be picked at the next switch); removing it takes an overridden Video out of the Rotation at once (a Current video that loses its override is replaced, with the Poster covering the gap).

**Blocked by:** 06, 08

**Status:** ready-for-agent

**Read first:** `.scratch/domain-modules/spec.md` (the spec), `CONTEXT.md` (glossary: use its terms), `docs/adr/0001-swiftpm-targets-per-context.md`, `docs/adr/0002-contexts-meet-in-one-coordinator.md`, `.claude/CODING_STANDARDS.md`.

**Ground rules for every ticket in this set:**
- Behaviour visible to the user is unchanged unless this ticket says otherwise; the log keeps today's lines (same causes and fields).
- `make build` (lint `--strict`, all tests, smoke, compile) is green before you open the PR. Do not run `make install` or `make uninstall` (they restart the user's wallpaper and can block on a keychain prompt); manual checks that need them are listed for the user in the PR.
- Contexts never import one another; they meet only in the coordinator (ADR 0002). A context depends only on the shared kernel.
- Stay inside the files this ticket owns; tickets run in parallel. If you must touch a shared file (package manifest, another context's coordinator file), keep the edit to the minimum lines and say why in the PR.
- Commits omit the Co-Authored-By trailer (user preference).

## Acceptance criteria

- [ ] Set Mode and Set FlashOverride (Video, on/off) commands with typed results and events
- [ ] Changes persist across a simulated relaunch (fake settings store)
- [ ] Application tests for both commands, including an unknown Mode rejected, an override for a Video not in the folder (decide and document), and the Current video losing its override
- [ ] `make build` green
