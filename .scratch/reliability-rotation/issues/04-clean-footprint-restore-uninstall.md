# 04: Clean footprint — Posters out of the folder, restore original wallpaper, full uninstall

**What to build:** The Wallpaper folder contains only the user's videos. Posters live in the app's Application Support folder under per-video names; a legacy hidden Poster file in the Wallpaper folder is removed. On first run the app records the user's original desktop picture for each screen. A restore command-line flag puts the original back, and `make uninstall` runs it before removing the app, the LaunchAgent, the Application Support folder and the app's preferences domain — leaving the Mac as it was.

**Blocked by:** 03

**Status:** done (manual checks pending install)

- [x] Poster written to Application Support with a per-video name and set as the desktop picture for every screen
- [x] Legacy Poster file removed from the Wallpaper folder on launch
- [x] Original desktop picture per screen recorded once (not overwritten on later runs)
- [x] Restore flag restores originals and exits without starting the UI
- [x] `make uninstall` restores, then removes app, agent, Application Support and preferences
- [x] README updated: what lives where, what uninstall removes, current-Space-only caveat
- [ ] `make build` green; `make install` (do not run uninstall on the user's machine except to verify restore, then reinstall) — build green (224 checks); install left to the orchestrator

## Comments

- Layout:
  - `Sources/Core/Footprint.swift` holds the decisions, tested in `Tests/FootprintTests.swift`:
    - `posterFileName(forVideoAt:file:)` gives `poster-<16 hex>.jpg`, an FNV-1a hash of path, size and mtime in ms. It doesn't use `Hasher` because that is seeded per process. A golden value pins the name, cross-checked with Python.
    - `stalePosters` lists Posters of videos no longer in the folder, so they can be pruned.
    - `OwnPictures` says whether a path is one of our Posters: anything in `posters/`, plus the legacy `.poster.jpg`.
    - `originalsToRecord` never overwrites a recorded screen. It adds a screen not recorded yet unless that screen already shows our Poster, because then its original is unknown.
    - `restorePlan` only touches screens that show our Poster. Each one gets its recorded original. If there is none, or that file no longer exists, it gets another screen's original. Failing that, it gets `/System/Library/CoreServices/DefaultDesktop.heic`.
    - `OriginalPictures` encodes to and from JSON.
  - `Sources/App/DesktopPictures.swift`:
    - `AppFiles` holds all the paths.
    - `DesktopPictures` reads and sets per-screen pictures with their scaling, clipping and fill options. Screens are keyed by display UUID.
    - It also records originals (at launch, and again before every Poster is set, so a newly connected display is recorded too) and implements `--restore-wallpaper`.
  - The originals are stored in `~/Library/Application Support/VideoWallpaper/original-desktop-pictures.json`. An unreadable file is logged and never overwritten.
  - `main.swift`:
    - At launch it records originals, removes the legacy `.poster.jpg`, and loads the Current video's saved Poster as the underlay.
    - On a video change it reuses the saved Poster, or exports a new one, sets it on every screen, and prunes stale Posters.
    - `--restore-wallpaper` is checked before any UI starts.
- Interpretations and deviations:
  - **On this Mac the true original is probably lost.** The existing install already set `~/Movies/LiveWallpaper/.poster.jpg` as the desktop picture, so on first launch every screen shows "our" Poster. Nothing gets recorded, and restore falls back to the macOS default picture. Before installing, the user can set their preferred picture in System Settings: it will then be recorded at the next launch. The app is stopped while it is re-launched by `make install`, and launch records the originals before the first Poster is set.
  - Restore leaves alone any picture the user chose themselves since install. Like setting the Poster, it only affects the current Space (documented in the README).
  - Stale-Poster pruning was not in this ticket; the spec puts pruning with the Phase 2 cache. I added it because per-video names would otherwise grow Application Support without limit. Ticket 06 can fold it into the cache prune.
  - `make uninstall` also deletes any leftover `.poster.jpg` in the video folder. It keeps the log in `~/Library/Logs/`. It warns, but carries on, if the restore fails or the app binary is missing.
- Manual checks after `make install`:
  1. Before installing, set your preferred desktop picture in System Settings, so that it is the one recorded.
  2. After install:
     - `~/Movies/LiveWallpaper/` contains no `.poster.jpg` (`ls -la`), and the log shows `removed legacy Poster`.
     - `~/Library/Application Support/VideoWallpaper/original-desktop-pictures.json` lists every display with your picture, and the log shows `recorded originals for screens=[…]`.
     - `posters/` holds one `poster-*.jpg` for the Current video, and every display's desktop picture is that file. To check, open System Settings → Wallpaper, or run `osascript -e 'tell app "System Events" to get picture of every desktop'`.
  3. Restart the agent (`launchctl unload` / `launchctl load`). The JSON is unchanged, because it is not overwritten. The underlay shows the Poster at once, not black, before the video starts.
  4. Drop a second video in. A second `poster-*.jpg` appears and becomes the desktop picture. Delete that video: its Poster is pruned on the next video change.
  5. Restore without uninstalling: `launchctl unload ~/Library/LaunchAgents/com.videowallpaper.plist`, then run `~/Applications/VideoWallpaper.app/Contents/MacOS/videowallpaper --restore-wallpaper`. It should print `[restore] screen=… picture=…` lines, exit 0, and show no window or Dock icon. Every display should show the recorded picture again. Then `launchctl load` again.
  6. Optionally, verify the full uninstall: run `make uninstall`, then check that the desktop picture was restored and that these are all gone: the app, `~/Library/LaunchAgents/com.videowallpaper.plist`, `~/Library/Application Support/VideoWallpaper/`, and the defaults domain (`defaults read com.evanscott.videowallpaper` should report that it does not exist). Then run `make install` again.
