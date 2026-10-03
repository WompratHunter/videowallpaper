# 06: Analysis and flash screener

**What to build:** Every video in the Wallpaper folder gets a one-time Analysis in the background (utility QoS, one at a time, skipped in Low Power Mode): mean relative luminance, maximum flashes per second, and a Poster taken from the frame closest to the clip's mean luminance. Results are cached in Application Support keyed by path + size + mtime and pruned when videos disappear. Videos over 3 flashes/s are Excluded and logged with their rate, unless their file name is in the `FlashOverride` preference (an array of file names). The Library exposes the eligible videos with their luminance. Until ticket 09, the newest *eligible* video plays.

**Blocked by:** 05

**Status:** ready-for-agent

- [ ] Flash counting is a pure core function: every frame, reduced resolution, 12×12 grid with overlapping 2×2 neighbourhoods plus full frame; flash = opposing relative-luminance changes ≥ 0.10 with darker state < 0.80; max in any 1 s window
- [ ] sRGB→linear via 256-entry lookup table; BT.709 weights
- [ ] Tests: synthetic square waves at 2/3/4/6 Hz classify correctly; slow drift not counted; a small-region flash is caught; tiers + override; Poster-frame choice; cache encode/decode/prune
- [ ] Smoke test: analyser on a generated 2 s clip with a known flash rate gives the expected classification
- [ ] The user's rain/lightning video measures ≤ 3/s and stays eligible (verify on the real file)
- [ ] README: honest wording — approximate screener for WCAG 2.3.1 general flash, luminance only, no red-flash test, not a conformance assessment; `FlashOverride` usage
- [ ] `make build` green; rebase on main before review; `make install` after merge
