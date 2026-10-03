# 06: Analysis and flash screener

**What to build:** Every video in the Wallpaper folder gets a one-time Analysis in the background (utility QoS, one at a time, skipped in Low Power Mode): mean relative luminance, maximum flashes per second, and a Poster taken from the frame closest to the clip's mean luminance. Results are cached in Application Support keyed by path + size + mtime and pruned when videos disappear. Videos over 3 flashes/s are Excluded and logged with their rate, unless their file name is in the `FlashOverride` preference (an array of file names). The Library exposes the eligible videos with their luminance. Until ticket 09, the newest *eligible* video plays.

**Blocked by:** 05

**Status:** done (installed 843fd3f; all 4 videos analysed, eligible=4, lucyna 1.5/s)

- [x] Flash counting is a pure core function: every frame, reduced resolution, 12×12 grid with overlapping 2×2 neighbourhoods plus full frame; flash = opposing relative-luminance changes ≥ 0.10 with darker state < 0.80; max in any 1 s window
- [x] sRGB→linear via 256-entry lookup table; BT.709 weights
- [x] Tests: synthetic square waves at 2/3/4/6 Hz classify correctly; slow drift not counted; a small-region flash is caught; tiers + override; Poster-frame choice; cache encode/decode/prune
- [x] Smoke test: analyser on a generated 2 s clip with a known flash rate gives the expected classification
- [x] The user's rain/lightning video measures ≤ 3/s and stays eligible (verify on the real file)
- [x] README: honest wording — approximate screener for WCAG 2.3.1 general flash, luminance only, no red-flash test, not a conformance assessment; `FlashOverride` usage
- [x] `make build` green; rebase on main before review; `make install` after merge (install is the user's step)

## Comments

- Built.
  - Core `Flash.swift`: sRGB→linear 256-entry table, BT.709 `relativeLuminance`, `FlashGrid` (12×12 cell means from a BGRA buffer; the full frame plus 121 overlapping 2×2 neighbourhoods), `TransitionDetector`, `FlashScreener` (streams frames, max transitions per region in any 1 s window, flashes = transitions / 2), `posterFrameIndex`, `flashVerdict` (withinLimit / excluded / overridden), `verdictsToLog` (log each Excluded/overridden video once per change).
  - Core `AnalysisCache.swift`: the cache index (path → size + mtime ms + Analysis, versioned JSON, prune), `screenEligible` and `videosToAnalyse` (newest first).
  - App `LibraryAnalyser.swift`: AVAssetReader decode at 192×108 BGRA into the screener; exact-time Poster frame. AVFoundation only, so the smoke test compiles it alone.
  - App `LibraryAnalysis.swift`: `LibraryAnalysisQueue`. A detached utility task, one at a time. Turning on `isPowerSaving` cancels a running Analysis (re-queued, logged `paused for Low Power Mode`) and starts none. It saves the Poster, then the cache, and logs `analysis video=… luminance=… flashes=…/s poster=…s took=…s`. A failed file is not retried until it changes.
  - `Library`: `videoToPlay()` is the newest *eligible* video; `eligibleVideos()` gives name, mtime and luminance; `flashOverrides` and `isPowerSaving` inputs. `onChange` fires only when the eligible set changes. Each Excluded (or overridden) video is logged once with its rate.
  - `LibraryPosters`: the export fallback uses the analysed Poster time instead of 5 s. A used saved Poster now also prunes stale ones, so the old 5 s Posters go.
- The transition algorithm (the prototype's `transitions()` was rewritten). A change is measured from the last extreme, not from the previous frame, so a fade spread over frames counts once. Before the first transition the running min and max are tracked. A rise needs `value − min ≥ 0.10` with `min < 0.80`; a fall needs `max − value ≥ 0.10` with `value < 0.80`. There is a 1e-9 tolerance, so exactly 0.10 counts. A window holds transitions less than 1 s apart, and flashes = transitions / 2 as a fraction. So 7 transitions in a second (a 3.5 Hz strobe) is 3.5/s and Excluded, the conservative reading; a lone change counts 0.5.
- Measured on the user's videos (read only, `.build/smoke ~/Movies/LiveWallpaper/*.mp4`, -O build: about 1 s CPU in total for all four):
  - capybara-anime-sunset-drive: luminance 0.299, 2.0 flashes/s, Poster at 5.70 s, 0.7 s wall.
  - final-fantasy-vii-main-menu: 0.037, 0.0/s, 0.65 s, 3.2 s.
  - lucyna-and-cat-rainy-neon-night (rain/lightning): 0.161, **1.5/s**, eligible: 3 opposing changes in its worst second. Under the earlier integer count it was 1/s, matching the prototype's 1.0/s; luminance matches the prototype's 0.16.
  - maomao-the-apothecary-diaries: 0.177, 0.0/s, 1.22 s, 6.4 s.
- Tested (`make test`): the LUT and weights; grid and regions from a padded BGRA buffer; full-frame square waves at 2, 3, 4 and 6 Hz × 24, 25, 30 and 60 fps; the 0.10 and 0.80 thresholds; 3.5 Hz Excluded at 24, 30 and 60 fps; slow drift and a 0.5 Hz pulse not counted; rain-like noise with lightning every 2 s at 1/s; a 2.8% region flash at 3 and 6 Hz caught; the Poster-frame choice (dark intro skipped, ties earliest); verdict tiers and override (exact file name); cache lookup, replace/touch, JSON round trip, wrong version, prune; eligibility; Analysis order.
- Smoke (`make smoke`, now part of `make build`): the real analyser on generated 2 s 30 fps H.264 clips. 3 Hz gives 3/s (eligible) and 5 Hz gives 5/s (Excluded). Clips go to the temp dir and are deleted.
- Wiring in `main.swift` (4 lines):
  - `Library(directory:analysisCache:)`.
  - `library.flashOverrides = { UserDefaults.standard.stringArray(forKey: "FlashOverride") ?? [] }` in `connectModules`.
  - `library.isPowerSaving = …` before `library.start()`.
  - `self?.library.isPowerSaving = isOn` in `powerStateChanged`.
- Also: `AppFiles.analysisCacheFile` (one line in `DesktopPictures.swift`); `Tests/main.swift` registers `runAnalysisCacheTests()`; `Makefile` gains `smoke`.
- Deviations and interpretations:
  - An unanalysed video is not eligible, since it hasn't been screened. On the first launch after install the cache is empty, so the newest video plays only after its Analysis (a few seconds; Analysis goes newest first). Until then the underlay is a still (Core `underlayCandidates`): the saved Poster of the video to play or of another non-Excluded video, else the current desktop picture, else any saved Poster; never black (fixed in review, see below). In Low Power Mode with an empty cache that still shows until Low Power Mode ends.
  - The Poster file name now includes the frame choice (golden value in `PosterFilesTests` updated), so analysed Posters get new URLs. macOS would otherwise keep showing its cached 5 s frame as the desktop picture.
  - A Poster is saved for Excluded videos too, so an override plays with a Poster at once.
  - The flash rate is transitions / 2 as a fraction (changed after review), so a 3.5 Hz strobe is Excluded. A `FlashOverride` edit is read whenever the app decides, but nothing re-decides until the next folder change or Analysis.
  - Folder changes reach the player only when the *eligible* set changes. A newly dropped video triggers `onChange` once analysed, not when it settles.
- Review (standards + spec), fixed:
  - Rounding the flash rate down let 3.5 Hz through.
  - A running Analysis now stops in Low Power Mode.
  - The log-once verdict transition moved to Core (`verdictsToLog`, tested).
  - `FlashVerdict.eligible` was renamed `withinLimit`, because overridden videos are eligible too.
  - The smoke paths in the Makefile are quoted.
  - The failed-Analysis set is pruned to present files.
- Review, accepted:
  - The queue's small bookkeeping (pending/running/failed) stays in App. Its decision, the order, is the Core `videosToAnalyse`.
  - `Analysis` repeats `FrameMeasurement`'s fields rather than nesting it, to keep the cache JSON flat.
  - The decode loop blocks one cooperative thread for a few seconds, one at a time. A Task is kept for cancellation.
  - First-launch black until the first Analysis: REJECTED in the second review (never black is the core promise); fixed with the launch underlay above.
- Manual checks after `make install`:
  - The log shows four `analysis video=…` lines on first launch with values close to those above, then `analysis eligible videos=4`. Next launch shows no `analysis` lines, because the cache is used.
  - `~/Library/Application Support/VideoWallpaper/analysis-cache.json` exists with 4 entries. `posters/` holds 4 new-named Posters, and the old ones are gone after the first Poster is shown.
  - The Lock screen and desktop picture show the new representative frame (not the 5 s frame).
  - Drop a strobing clip (e.g. generate one with `make smoke`-style code, or any >3/s video). It logs `flash excluded video=… flashes=N/s` and doesn't play. Then `defaults write com.evanscott.videowallpaper FlashOverride -array "<name>"` and touch the folder (or drop another file): it logs `flash override …` and plays.
  - Delete a video: its cache entry is pruned.
  - In Low Power Mode, a newly dropped video is not analysed until Low Power Mode ends.
  - Delete the cache and Posters, then relaunch: the screen shows the current desktop picture (log `launch no screened video yet; underlay=…`), never black, until the first video is analysed and plays.
- Second review, fixed:
  - Never black during the first Analysis: launch underlay chosen by Core `underlayCandidates` (tested), unscreened videos still never play.
  - A Low Power Mode cancellation reported by AVFoundation as its own error is re-queued, not marked failed.
  - README: a `FlashOverride` edit takes effect at the next launch or folder change, not immediately.
- Second review, verified: flash rate is transitions / 2 in any half-open 1 s window per region (122 regions: full frame + 121 overlapping 2×2 of 12×12), ≤3 eligible, >3 Excluded, 0.10 change with darker state < 0.80; utility QoS, one at a time, LPM cancel/skip; cache keyed path + size + mtime, version mismatch re-analyses, prune touches only cache entries and app-named Posters; smoke clips deleted, deterministic.
