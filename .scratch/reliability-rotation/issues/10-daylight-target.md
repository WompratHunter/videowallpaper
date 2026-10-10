# 10: Daylight-driven Target brightness

**What to build:** In `dynamic` Mode, the Rotation follows Daylight instead of Light/Dark appearance. Daylight (0–1) comes from the sun's position, computed locally from the Mac's location: 0 below −6°, 1 above +25°, smoothstep between. Daylight is the Target brightness, a percentile in the eligible videos' luminance ranking. The pick order is: a newly added video first; then random among unplayed-this-Pass videos within ±0.15 of the target rank, or the nearest unplayed one if that window is empty (and within ΔL ≤ 0.08 of the Current video while Visible); if none while Visible, the in-band video nearest the target; if still none, replay the played video nearest the target (never the Current one). A Current video more than 0.4 of rank from the target makes a switch due regardless of Dwell, only at an Unseen or Veiled moment. Appearance only picks the default Mode (Auto → `dynamic`, else `all`) and no longer triggers switches. Location comes from a one-shot CoreLocation fix at launch, on wake and on time-zone change, then a cached fix (rounded to ~0.1°, same time zone only), then `zone.tab` coordinates for the current time zone. Permission is requested only when the effective Mode is `dynamic`, never again after a denial.

**Blocked by:** 09 (done)

**Status:** ready-for-agent

- [ ] Sun position, Daylight curve, target → pick order, early-switch rule and location source chain are pure core functions with tests: NOAA reference sunrise/sunset for several cities and dates (±2 min) including polar day and night; curve endpoints and midpoint; all four pick steps and new-video-beats-target; 0.4 threshold; cache rejected in a different time zone; `zone.tab` lookup
- [ ] Location provider wraps CoreLocation (one-shot requests, authorization handling, cache in Application Support) behind one Daylight interface so weather can be added later (ticket 11)
- [ ] Reuse the existing off-Mode path in `Sources/Core/Rotation.swift` for the early switch (rank > 0.4 from target replaces "outside the preferred half"); appearance no longer makes a video off-Mode and is used only for the default Mode
- [ ] Makefile signs the `.app` with the "Apple Development" identity, ad-hoc fallback; links CoreLocation; `Info.plist` gains `NSLocationUsageDescription`; grant survives `make install` (verify)
- [ ] `make uninstall` prints how to remove the Location Services entry
- [ ] Logs: switch lines add Daylight, Target brightness, location source (fix / cache / timezone); authorization changes and new fixes logged with rounded coordinates only
- [ ] Debug-only clock/location override (not user-facing), alongside the existing debug Dwell scale, for the manual check
- [ ] Manual check: simulated dusk with ≥ 3 videos of differing brightness walks toward darker videos; lock/unlock at simulated night with a bright Current video triggers an early switch; denying Location Services falls back to the time zone and logs it
- [ ] README: `dynamic` described as Daylight-driven, the location prompt, privacy (no network calls by the app, no precise coordinates logged)
- [ ] `make build` green; rebase on main before review; `make install` after merge
