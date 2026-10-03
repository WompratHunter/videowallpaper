# 01: Test harness, build gate and wake-state logging

**What to build:** A developer runs `make build` and gets lint plus a passing test run before anything compiles into the app. The app now writes timestamped, unbuffered lines to its log (stderr, which the LaunchAgent already routes to the log file) at launch and on every wake/unlock, recording the player's status, item status and error, time-control status, waiting reason, and whether playback time advanced. This is the diagnostic that proves or disproves the black-screen root cause. Phase 1 of `.scratch/reliability-rotation/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Pure logic lives in a Foundation-only core location that the test build compiles automatically; the app build compiles it too
- [ ] Plain `swiftc` test runner with a tiny check helper that exits non-zero on failure; one test suite file per area, registered in the runner's entry point
- [ ] `make build` depends on lint and test; a failing test stops `make install`
- [ ] SwiftLint covers all app, core and test Swift sources; `make build` is lint-clean
- [ ] Logging helper writes timestamped lines to stderr without `print`; launch and every wake/unlock log one player-state line
- [ ] `.claude/CODING_STANDARDS.md` gains a short Testing section (harness, seam = core logic, what must be tested, `make build` gate)
- [ ] At least one real test exists (e.g. for the timestamp/log-line formatting or a trivial core helper) and passes
- [ ] `make install` succeeds and the log file shows the launch line
