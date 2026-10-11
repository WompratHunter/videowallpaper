# 04: Daylight context (parallel)

**What to build:** Sun position, the Daylight curve and location resolution live in the Daylight context. CoreLocation goes behind a location port, `zone.tab` behind a time-zone-places port, and the clock comes from the clock port (the debug clock override stays debug-only). Daylight publishes its level and location source (fix / cache / time zone, never coordinates) in its snapshot slice, and events for authorization changes and new fixes (rounded coordinates only in the log, as today). Location Services is still asked for only when `dynamic` Mode wants Daylight.

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

- [ ] Daylight domain and adapters moved into the Daylight target
- [ ] Location and time-zone-places ports with today's adapters and fakes
- [ ] Daylight events and snapshot slice; log lines unchanged; precise coordinates never logged or in the snapshot
- [ ] Daylight suites converted to native swift-testing
- [ ] Application tests: denied location falls back to the time zone source; a cached fix from another time zone is ignored; Location Services is not requested in `all` Mode
- [ ] `make build` green
