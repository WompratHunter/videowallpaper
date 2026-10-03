# 05: Prefactor — split into modules for parallel Phase 2 work

**What to build:** No behaviour change. The app is reorganised into the spec's deep modules so Phase 2 tickets can proceed in parallel without editing the same code: an entry/wiring file (app delegate, notifications, the single timer, settings reads), a Player module (shared player, layers, Recovery), a Library module (Wallpaper folder watch, settle, newest-video selection, Poster export), and an empty Visibility module seam. Core logic files are split per area (Recovery, Library, Visibility, Flash) and test suites likewise, so each Phase 2 ticket owns its own files.

**Blocked by:** 04

**Status:** ready-for-agent

- [x] Multi-file build works (entry file is `main.swift`); Makefile and lint pick up all files
- [x] Each module exposes a small interface; wiring is the only place modules meet
- [x] Per-area core-logic and test files exist (empty placeholders allowed for Visibility/Flash), registered in the test runner
- [x] `.claude/CODING_STANDARDS.md` updated: the "single-file app" description and file-organisation rules reflect the module layout (so review doesn't flag the split)
- [x] Behaviour identical to after ticket 04 (all tests pass, manual smoke: video plays, Poster set): 225/225 checks pass and two reviews found no behaviour difference; the manual smoke is pending `make install`
- [ ] `make build` green; `make install`: build green; install left to the orchestrator

## Comments

- Module map. `Sources/App/main.swift` is the only place modules meet.
  - **Wiring** (`main.swift`, `AppDelegate`): `connectModules()` sets each module's callbacks, `applicationDidFinishLaunching` runs the launch order (unchanged), it observes notifications (sleep, wake, session, unlock, screen parameters, power), runs the one 5 s tick (tolerance 2 s), and does settings reads (none yet). Also the `--restore-wallpaper` entry point.
  - **Player**, owned by 08:
    - `Player.swift`: `show(_:at:)`, `start()`, `apply(PlaybackEvent)`, `healthTick()`, `verifyPlayback(cause:)`, `resetBackoff(on:)`, `folderChanged(newest:)`, `recover(cause:detail:)`, `makeLayers(frame:)`, `setPoster(_:)`, `video`, plus the `videoProvider` and `onVideoChange` callbacks.
    - `PlayerLayers.swift`: every window's Poster and video layer, through `make(frame:)`, `attach(_ player:)` and `setPoster(_:)`. This is where the crossfade's second layer pair goes.
    - `PlayerState.swift`: maps AV state to `PlayerStateReport` and `hasFailed`.
    - Core: `Recovery.swift`, `PlaybackGate.swift`, `PlayerStateReport.swift`; a new `Core/Crossfade.swift` for any pure fade state. Tests in the matching suites.
  - **Library**, owned by 06:
    - `Library.swift`: `start()`, `videoToPlay()` (newest settled; becomes "newest eligible" in 06 and the Rotation pick's input in 09) and the `onChange(URL?)` callback. It holds the folder watch, the settle check and `videoSnapshot`.
    - `LibraryPosters.swift`: `savedPoster(for:)` and `poster(for:use:)`. `use` returns false when the video is no longer current; a freshly saved Poster that was used prunes the stale ones. The 5 s export frame lives here, and the Poster-frame choice replaces it.
    - 06 adds the Analysis queue and cache as more `Library…` files.
    - Core: `WallpaperFolder.swift`, `PosterFiles.swift` and `Flash.swift` (placeholder), with tests in `WallpaperFolderTests`, `PosterFilesTests` and `FlashTests` (empty). The cache index may go in a new `Core/AnalysisCache.swift`.
  - **Visibility**, owned by 07:
    - `Visibility.swift`: `state` and `onChange(VisibilityState)`. Nothing feeds it yet, so it stays `.visible`.
    - Core: `VisibilityClassification.swift` (`VisibilityState`, `isEveryWindowOccluded`), with tests in `VisibilityClassificationTests`.
  - **WallpaperWindows** (`WallpaperWindows.swift`): `rebuild()`, `reassert()` and `onOcclusionChange(Bool)`. It holds the per-screen windows, which host `player.makeLayers`, and the occlusion observer.
  - **DesktopPictures.swift**: `AppFiles` paths and `DesktopPictures.setPoster`, `recordOriginals` and `restoreOriginals`. The Core side is `Footprint.swift`, tested in `FootprintTests`. 09 calls `setPoster` on a switch through the wiring.
  - **Rotation**, owned by 09: Core `Rotation.swift` (placeholder) and `RotationTests` (empty). 09 adds the switch scheduler as a new App file plus wiring.
  - Every suite is already registered in `Tests/main.swift`, so 06, 07 and 08 don't need to edit it.
- Expected wiring touches in Phase 2. Each is a line or two in `main.swift`; 06 and 07 may both touch the notification handlers, so rebase before review.
  - 06: Low Power Mode on `powerStateChanged`, and perhaps a `FlashOverride` read.
  - 07: point `windows.onOcclusionChange` and the sleep, session and unlock handlers at `visibility` as well, and wire `visibility.onChange`.
  - 08: change `library.onChange` to pass a fade duration.
- Deviations and interpretations:
  - The layout was already multi-file (`main.swift` entry since ticket 01), so the split deepened the existing files and did not start from one file.
  - Poster storage was split out of `Core/Footprint.swift` into `Core/PosterFiles.swift`, so that 06's cache prune doesn't touch the desktop-picture code.
  - The occlusion observer now registers at the end of the first `windows.rebuild()` instead of in `observeSystemEvents()`. Both run in the same synchronous launch, so behaviour is the same.
  - `Library` cancels its folder watch in `deinit`. It never deallocates, so this is only hygiene.
  - Visibility gets no inputs yet. Inventing input methods before 07 designs them would be speculative.
- Review (standards + spec):
  - No behaviour regressions were found.
  - Fixed: Library helpers made private/static; the visibility suite is named after its Core area; ticket numbers dropped from comments; Visibility imports Foundation only.
  - Accepted: `Player.makeLayers`/`setPoster` forward to `PlayerLayers` so windows don't see it; the AV-name switches were moved unchanged.
- Manual check after `make install`: the launch lines match those of ticket 04 (`launch`, `occlusion windows=N`, `playing video=…`), the video plays on every display, and the Current video's Poster is the desktop picture.
