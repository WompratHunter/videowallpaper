# 01: SwiftPM package, behaviour unchanged

**What to build:** The app is built from a SwiftPM package instead of hand-listed `swiftc` invocations, with no change in behaviour. Today's `Sources/Core` becomes a legacy `Core` target and `Sources/App` a legacy `App` target (plus a thin executable target for the entry point), so later tickets can move code out of them context by context. The existing check-based test runner runs under `swift test` through swift-testing: the `check` helpers record swift-testing issues instead of exiting, and one test runs every existing suite, so all ~500 checks still gate the build. The analyser smoke test still runs. The Makefile keeps every target (`build`, `test`, `smoke`, `lint`, `install`, `uninstall`, `debug`) but drives `swift build` / `swift test`; `install` still assembles, signs and loads the `.app` exactly as today from the release product, and `debug` builds the debug configuration (which defines `DEBUG`, keeping the debug-only overrides).

**Blocked by:** None (can start immediately). Precondition: Daylight (reliability-rotation ticket 10) is on `main`; it is.

**Status:** ready-for-agent

**Read first:** `.scratch/domain-modules/spec.md` (the spec), `CONTEXT.md` (glossary: use its terms), `docs/adr/0001-swiftpm-targets-per-context.md`, `docs/adr/0002-contexts-meet-in-one-coordinator.md`, `.claude/CODING_STANDARDS.md`.

**Ground rules for every ticket in this set:**
- Behaviour visible to the user is unchanged unless this ticket says otherwise; the log keeps today's lines (same causes and fields).
- `make build` (lint `--strict`, all tests, smoke, compile) is green before you open the PR. Do not run `make install` or `make uninstall` (they restart the user's wallpaper and can block on a keychain prompt); manual checks that need them are listed for the user in the PR.
- Contexts never import one another; they meet only in the coordinator (ADR 0002). A context depends only on the shared kernel.
- Stay inside the files this ticket owns; tickets run in parallel. If you must touch a shared file (package manifest, another context's coordinator file), keep the edit to the minimum lines and say why in the PR.
- Commits omit the Co-Authored-By trailer (user preference).

## Acceptance criteria

- [ ] Package manifest with legacy `Core` (Foundation-only), legacy `App`, executable, smoke runner and test targets; the analyser code the smoke test needs is shared through a target rather than a duplicated file
- [ ] `swift test` runs every existing suite via swift-testing; a deliberately failing check fails `make build` (verify, then revert)
- [ ] At least one new native swift-testing `@Test` proves the framework works under `make test`
- [ ] `make build`, `make debug` and `make smoke` work; the release binary and `.app` layout used by `make install` are unchanged (inspect the recipe; don't run install)
- [ ] SwiftLint covers `Package.swift`, all `Sources/` and `Tests/` and stays `--strict` clean
- [ ] `.gitignore` covers SwiftPM build output
- [ ] README requirements/build section mentions the package (full Xcode or a Swift 6 toolchain)
