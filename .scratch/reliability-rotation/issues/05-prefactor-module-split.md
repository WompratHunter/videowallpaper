# 05: Prefactor — split into modules for parallel Phase 2 work

**What to build:** No behaviour change. The app is reorganised into the spec's deep modules so Phase 2 tickets can proceed in parallel without editing the same code: an entry/wiring file (app delegate, notifications, the single timer, settings reads), a Player module (shared player, layers, Recovery), a Library module (Wallpaper folder watch, settle, newest-video selection, Poster export), and an empty Visibility module seam. Core logic files are split per area (Recovery, Library, Visibility, Flash) and test suites likewise, so each Phase 2 ticket owns its own files.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] Multi-file build works (entry file is `main.swift`); Makefile and lint pick up all files
- [ ] Each module exposes a small interface; wiring is the only place modules meet
- [ ] Per-area core-logic and test files exist (empty placeholders allowed for Visibility/Flash), registered in the test runner
- [ ] `.claude/CODING_STANDARDS.md` updated: the "single-file app" description and file-organisation rules reflect the module layout (so review doesn't flag the split)
- [ ] Behaviour identical to after ticket 04 (all tests pass, manual smoke: video plays, Poster set)
- [ ] `make build` green; `make install`
