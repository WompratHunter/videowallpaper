# 02: Tracer: shared kernel, Application layer, coordinator, events, snapshot and Preferences

**What to build:** Lays down the shape every context ticket copies, end to end, and prefactors the legacy code so six context tickets can then run in parallel without touching each other's files. The app still behaves exactly as before.

- **Targets:** the manifest declares a shared-kernel target, one library target per context (Library, Rotation, Playback, Presence, Daylight, Desktop; empty apart from a placeholder), `Application`, `Platform`, a test-support target of fakes, and one test target per context plus one for `Application`. Legacy `Core`/`App` depend on all of them, so later tickets only fill targets in.
- **Shared kernel:** Video identity (file name), Version (size + mtime in ms), Eligible Video (identity, Version, mean luminance), Presence (Unseen/Veiled/Visible), and the time types ports share. Legacy code switches to them.
- **Prefactor:** every legacy file belongs to exactly one context. Cross-context helpers move to their owner: brightness ranking and the Presence-to-transition rule (minimum Dwell, fade, big-jump allowance) belong to Rotation; Rotation gets its own fade durations instead of reading Playback's; Rotation is told "away from desk" (lock, sleep, session) as its own input rather than reading Presence inputs. App paths belong to Platform and are passed to modules at construction.
- **Application layer:** a coordinator that takes over every route in today's entry point, written as one coordinator extension (file) per context, preserving the ordering rules in the spec (Dwell hears of a lock before Presence; a folder change reaches Rotation before Playback; the Poster follows every video change; a Presence change triggers a decision). The app delegate only observes system notifications, owns the tick, composes adapters and forwards to the coordinator.
- **Events:** one app event enum with one case per context wrapping that context's own event enum (declared in each context target), delivered in order on the main actor; a log-sink subscriber in Platform renders events to today's log lines. Migrate one path end to end (the eligible-set-changed / folder-change line) to prove it; the other lines move with their contexts.
- **Snapshot:** an immutable value composed of one slice per context (slice types declared in the context targets; empty placeholders allowed), with a change notification.
- **Preferences:** a typed value (Mode setting, FlashOverride names; fields for Enabled, Wallpaper folder and Launch at login reserved for later tickets) loaded through a settings port with a `UserDefaults` adapter using today's keys; the raw `UserDefaults` reads in the wiring are gone.
- **Ports and fakes:** a clock/tick port; the settings port; fakes for both in test support. The first Application test drives launch with a fake clock: settled and analysed videos lead to a first switch event and a snapshot naming the Current video.

**Blocked by:** 01

**Status:** ready-for-agent

**Read first:** `.scratch/domain-modules/spec.md` (the spec), `CONTEXT.md` (glossary: use its terms), `docs/adr/0001-swiftpm-targets-per-context.md`, `docs/adr/0002-contexts-meet-in-one-coordinator.md`, `.claude/CODING_STANDARDS.md`.

**Ground rules for every ticket in this set:**
- Behaviour visible to the user is unchanged unless this ticket says otherwise; the log keeps today's lines (same causes and fields).
- `make build` (lint `--strict`, all tests, smoke, compile) is green before you open the PR. Do not run `make install` or `make uninstall` (they restart the user's wallpaper and can block on a keychain prompt); manual checks that need them are listed for the user in the PR.
- Contexts never import one another; they meet only in the coordinator (ADR 0002). A context depends only on the shared kernel.
- Stay inside the files this ticket owns; tickets run in parallel. If you must touch a shared file (package manifest, another context's coordinator file), keep the edit to the minimum lines and say why in the PR.
- Commits omit the Co-Authored-By trailer (user preference).

## Acceptance criteria

- [ ] Manifest declares every target listed; contexts depend only on the shared kernel (compile-checked); `Application` depends on contexts and ports, never adapters
- [ ] Every legacy file is owned by one context; the mapping is recorded in the PR description and in a short note appended to this ticket, so 03-08 know which files are theirs
- [ ] No route remains in the entry point; each context's routes live in that context's coordinator file
- [ ] Typed app event enum and log sink exist; the eligible-set / folder-change line is emitted from an event and reads exactly as before
- [ ] Snapshot with per-context slices and a change notification; Preferences via the settings port with today's keys
- [ ] Application test with fake clock and settings passes; fakes live in test support
- [ ] Coding standards gain a short section describing contexts, shared kernel, Application, ports, coordinator and test targets (full rewrite comes in 13)
- [ ] `make build` green; app behaviour and log unchanged
