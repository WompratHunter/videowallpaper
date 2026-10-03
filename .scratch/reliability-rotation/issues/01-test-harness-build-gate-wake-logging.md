# 01: Test harness, build gate and wake-state logging

**What to build:** A developer runs `make build` and gets lint plus a passing test run before anything compiles into the app. The app now writes timestamped, unbuffered lines to its log (stderr, which the LaunchAgent already routes to the log file) at launch and on every wake/unlock, recording the player's status, item status and error, time-control status, waiting reason, and whether playback time advanced. This is the diagnostic that proves or disproves the black-screen root cause. Phase 1 of `.scratch/reliability-rotation/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] Pure logic lives in a Foundation-only core location that the test build compiles automatically; the app build compiles it too
- [x] Plain `swiftc` test runner with a tiny check helper that exits non-zero on failure; one test suite file per area, registered in the runner's entry point
- [x] `make build` depends on lint and test; a failing test stops `make install`
- [x] SwiftLint covers all app, core and test Swift sources; `make build` is lint-clean
- [x] Logging helper writes timestamped lines to stderr without `print`; launch and every wake/unlock log one player-state line
- [x] `.claude/CODING_STANDARDS.md` gains a short Testing section (harness, seam = core logic, what must be tested, `make build` gate)
- [x] At least one real test exists (e.g. for the timestamp/log-line formatting or a trivial core helper) and passes
- [x] `make install` succeeds and the log file shows the launch line

## Comments

- Layout: app moved to `Sources/App/main.swift` (multi-file swiftc needs a `main.swift` entry); core logic in `Sources/Core/`, tests in `Tests/` (`make test` compiles `Sources/Core/*.swift` + `Tests/*.swift`).
- `make build` now compiles into `.build/videowallpaper`; only `make install` copies the binary into `~/Applications/VideoWallpaper.app` (via `install`, i.e. a new inode, so the running binary is not overwritten in place). Lint runs with `--strict`.
- Player-state lines are logged per window (`screen=N`) because each window still owns its own player; ticket 02's shared player reduces this to one line per event. Causes logged: `launch`, `wake` (system), `screens-wake`, `session-active`, `unlock` (`com.apple.screenIsUnlocked`), plus a `screens-sleep` line. Each samples playback time, then logs 1 s later with `advanced=yes|no|unknown`.
- Deferred to the orchestrator: `make install` and confirming the launch line in `~/Library/Logs/videowallpaper.log` (agent was not allowed to install or run alongside the user's app). The line format is covered by tests.
