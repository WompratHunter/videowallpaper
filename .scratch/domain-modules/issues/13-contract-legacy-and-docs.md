# 13: Contract: retire legacy targets; Platform only composes; docs

**What to build:** The migration is finished. The legacy `Core` and `App` targets and the old check runner are deleted; every test is native swift-testing in its context's or the Application's test target. The entry point only observes system notifications, owns the tick and composes real adapters; every log line comes from an event through the log sink. The log is compared with today's: run the debug build against a temporary folder with a few generated clips and diff the cause/field shape of each line type against a log from before the migration (build `main` from before ticket 01 for the reference). `CODING_STANDARDS.md` is rewritten for the package layout, contexts, shared kernel, Application layer, ports, coordinator and swift-testing (replacing "no SwiftPM, no Xcode project"), and the README's "How it works" and "What lives where" describe the new shape.

**Blocked by:** 03, 04, 05, 06, 07, 08

**Status:** ready-for-agent

**Read first:** `.scratch/domain-modules/spec.md` (the spec), `CONTEXT.md` (glossary: use its terms), `docs/adr/0001-swiftpm-targets-per-context.md`, `docs/adr/0002-contexts-meet-in-one-coordinator.md`, `.claude/CODING_STANDARDS.md`.

**Ground rules for every ticket in this set:**
- Behaviour visible to the user is unchanged unless this ticket says otherwise; the log keeps today's lines (same causes and fields).
- `make build` (lint `--strict`, all tests, smoke, compile) is green before you open the PR. Do not run `make install` or `make uninstall` (they restart the user's wallpaper and can block on a keychain prompt); manual checks that need them are listed for the user in the PR.
- Contexts never import one another; they meet only in the coordinator (ADR 0002). A context depends only on the shared kernel.
- Stay inside the files this ticket owns; tickets run in parallel. If you must touch a shared file (package manifest, another context's coordinator file), keep the edit to the minimum lines and say why in the PR.
- Commits omit the Co-Authored-By trailer (user preference).

## Acceptance criteria

- [ ] No legacy targets or check runner remain; no direct logging outside the log sink
- [ ] Only Platform depends on adapters; no context imports another
- [ ] Log line shapes match the pre-migration log (diff summary in the PR)
- [ ] Coding standards and README updated; SwiftLint config matches the new layout
- [ ] `make build` green
