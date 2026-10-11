# 11: Choose Wallpaper folder

**What to build:** A future UI can point the app at any folder. The command checks the folder is readable, saves it in Preferences, re-points the folder-access adapter, and the Library rescans: the Rotation switches to the new folder's Videos with the Poster covering the gap (never black), and Videos already analysed elsewhere are analysed anew (the cache is keyed by path). The default stays `~/Movies/LiveWallpaper`; a stored folder that has gone missing at launch falls back to the default with a logged event. This stores a plain path; the App Store phase swaps in a security-scoped bookmark behind the same port.

**Blocked by:** 06, 07, 08

**Status:** ready-for-agent

**Read first:** `.scratch/domain-modules/spec.md` (the spec), `CONTEXT.md` (glossary: use its terms), `docs/adr/0001-swiftpm-targets-per-context.md`, `docs/adr/0002-contexts-meet-in-one-coordinator.md`, `.claude/CODING_STANDARDS.md`.

**Ground rules for every ticket in this set:**
- Behaviour visible to the user is unchanged unless this ticket says otherwise; the log keeps today's lines (same causes and fields).
- `make build` (lint `--strict`, all tests, smoke, compile) is green before you open the PR. Do not run `make install` or `make uninstall` (they restart the user's wallpaper and can block on a keychain prompt); manual checks that need them are listed for the user in the PR.
- Contexts never import one another; they meet only in the coordinator (ADR 0002). A context depends only on the shared kernel.
- Stay inside the files this ticket owns; tickets run in parallel. If you must touch a shared file (package manifest, another context's coordinator file), keep the edit to the minimum lines and say why in the PR.
- Commits omit the Co-Authored-By trailer (user preference).

## Acceptance criteria

- [ ] Choose Wallpaper folder command with typed failures (missing, unreadable, not a folder) and an event; the snapshot shows the folder
- [ ] Switching folders never leaves the window without a Poster or video
- [ ] Application tests: switch to a folder with videos; switch to an empty folder (rests on the Poster); unreadable folder rejected; missing stored folder at launch falls back
- [ ] `make build` green
