# 04: Clean footprint — Posters out of the folder, restore original wallpaper, full uninstall

**What to build:** The Wallpaper folder contains only the user's videos. Posters live in the app's Application Support folder under per-video names; a legacy hidden Poster file in the Wallpaper folder is removed. On first run the app records the user's original desktop picture for each screen. A restore command-line flag puts the original back, and `make uninstall` runs it before removing the app, the LaunchAgent, the Application Support folder and the app's preferences domain — leaving the Mac as it was.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] Poster written to Application Support with a per-video name and set as the desktop picture for every screen
- [ ] Legacy Poster file removed from the Wallpaper folder on launch
- [ ] Original desktop picture per screen recorded once (not overwritten on later runs)
- [ ] Restore flag restores originals and exits without starting the UI
- [ ] `make uninstall` restores, then removes app, agent, Application Support and preferences
- [ ] README updated: what lives where, what uninstall removes, current-Space-only caveat
- [ ] `make build` green; `make install` (do not run uninstall on the user's machine except to verify restore, then reinstall)
