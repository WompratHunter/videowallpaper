# 14: Swift 6 language mode and final verification

**What to build:** The package builds in Swift 6 language mode with strict concurrency and no warnings, so a SwiftUI UI can bind to the snapshot safely in the next phase. Domain types crossing actors are `Sendable`; the Application layer, contexts' services and adapters are main-actor isolated; AV/KVO/notification callbacks hop to the main actor at the adapter boundary. The PR carries the manual checklist for the user to run on the installed app: rename the playing Video, sleep and wake, Ghostty in front, Low Power Mode, Disable/Enable, quit restores, `make uninstall` restores then reinstall.

**Blocked by:** 09, 10, 11, 12, 13

**Status:** ready-for-agent

**Read first:** `.scratch/domain-modules/spec.md` (the spec), `CONTEXT.md` (glossary: use its terms), `docs/adr/0001-swiftpm-targets-per-context.md`, `docs/adr/0002-contexts-meet-in-one-coordinator.md`, `.claude/CODING_STANDARDS.md`.

**Ground rules for every ticket in this set:**
- Behaviour visible to the user is unchanged unless this ticket says otherwise; the log keeps today's lines (same causes and fields).
- `make build` (lint `--strict`, all tests, smoke, compile) is green before you open the PR. Do not run `make install` or `make uninstall` (they restart the user's wallpaper and can block on a keychain prompt); manual checks that need them are listed for the user in the PR.
- Contexts never import one another; they meet only in the coordinator (ADR 0002). A context depends only on the shared kernel.
- Stay inside the files this ticket owns; tickets run in parallel. If you must touch a shared file (package manifest, another context's coordinator file), keep the edit to the minimum lines and say why in the PR.
- Commits omit the Co-Authored-By trailer (user preference).

## Acceptance criteria

- [ ] Swift 6 language mode on every target; zero concurrency warnings
- [ ] All tests and the smoke test pass; `make build` green
- [ ] Manual checklist in the PR for the user
