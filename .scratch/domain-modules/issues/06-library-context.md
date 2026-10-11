# 06: Library context (parallel)

**What to build:** The Wallpaper folder, settle check, Analysis, flash screening, FlashOverride application and Posters live in the Library context. Folder access (resolve, list with size/mtime, watch) and the analyser go behind ports with today's adapters; the folder location is passed in, not read from a global. Analysis runs as an async task off the main actor and hands back plain values, removing the `@unchecked Sendable`. Library publishes the Video catalogue in its snapshot slice: every Video with its Version and catalogue status (settling, analysing, analysis failed, Excluded with rate, overridden, eligible), and events (settled, Analysis done/failed, Excluded, overridden, eligible set changed) rendering today's log lines. Analysis and Poster are keyed by Version; FlashOverride by Video identity.

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

- [ ] Library domain and adapters moved into the Library target; the analyser is shared with the smoke runner from there
- [ ] Folder-access and analyser ports with today's adapters; an in-memory folder fake and a scriptable analyser fake
- [ ] Video catalogue with catalogue status in the snapshot; Library events; log lines unchanged
- [ ] No `@unchecked Sendable`; Analysis off the main actor; Low Power Mode still cancels and re-queues
- [ ] Library suites converted to native swift-testing; the smoke test still runs in `make build`
- [ ] Application tests: a copied file is ignored until settled, then analysed, then eligible and played next; an over-limit video is Excluded until overridden; a replaced Version is re-analysed and keeps its override; a rename is a new Video
- [ ] `make build` green
