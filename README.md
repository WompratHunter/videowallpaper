# videowallpaper

Native macOS video wallpaper. No third-party app — just AVFoundation, compiled once with the system Swift compiler.

Plays every `.mp4`, `.mov` or `.m4v` in `~/Movies/LiveWallpaper/` in turn, switching with a slow crossfade when you're unlikely to notice. Drop in a new file and, once it has been analysed (a few seconds), it plays next.

## Requirements

- macOS 14+ (Sonoma or later)
- Xcode Command Line Tools: `xcode-select --install`
- SwiftLint (`make build` lints first): `brew install swiftlint`

## Install

```sh
git clone https://github.com/evanscott/videowallpaper
cd videowallpaper
make install
```

Then drop a `.mp4` into `~/Movies/LiveWallpaper/`.

## Usage

| Action | Command |
|---|---|
| Add a video | Drop a `.mp4` into `~/Movies/LiveWallpaper/`; it plays at the next switch |
| Choose light or dark videos | `defaults write com.evanscott.videowallpaper Mode -string dark` (see [Settings](#settings)) |
| Stop | `launchctl unload ~/Library/LaunchAgents/com.videowallpaper.plist` |
| Start | `launchctl load ~/Library/LaunchAgents/com.videowallpaper.plist` |
| Restore original desktop picture | Stop, then `~/Applications/VideoWallpaper.app/Contents/MacOS/videowallpaper --restore-wallpaper` |
| Uninstall | `make uninstall` |
| Logs | `tail -f ~/Library/Logs/videowallpaper.log` (launch, wake and unlock lines include player state; `[rotation]` lines show each switch) |
| Lint + test + compile | `make build` |

## What lives where

| Path | What |
|---|---|
| `~/Movies/LiveWallpaper/` | Your videos, and nothing else: the app writes no files here |
| `~/Applications/VideoWallpaper.app` | The app |
| `~/Library/LaunchAgents/com.videowallpaper.plist` | Starts the app at login and restarts it if it quits |
| `~/Library/Application Support/VideoWallpaper/posters/` | One Poster (still frame) per video, named from the video's path, size and modification date; Posters of deleted videos are pruned |
| `~/Library/Application Support/VideoWallpaper/analysis-cache.json` | Each video's Analysis (mean luminance, flash rate, Poster), keyed by path, size and modification date; entries for deleted or replaced videos are pruned |
| `~/Library/Application Support/VideoWallpaper/original-desktop-pictures.json` | Your desktop picture per display, recorded at first launch (and for a newly connected display, before its first Poster) and never overwritten |
| `com.evanscott.videowallpaper` defaults domain | The app's preferences |
| `~/Library/Logs/videowallpaper.log` | The log |

Versions before this one wrote a hidden `.poster.jpg` into the video folder; the app deletes it on launch.

## Analysis and the flash screener

Each video is analysed once, in the background at low priority, one at a time, and not in Low Power Mode (one in progress stops, and a new video waits until Low Power Mode ends). Analysis decodes every frame at reduced resolution to measure the video's mean brightness (relative luminance) and its flash rate, and takes the Poster from the frame closest to the mean brightness, so the Lock screen doesn't show a dark intro frame. A 20 s 4K video takes a few seconds and under half a second of CPU. A video plays only once it has been analysed; until then the screen shows a saved Poster or, on a first install, your current desktop picture, never black.

The flash check is an **approximate screener** modelled on the WCAG 2.3.1 general flash threshold, not a conformance assessment:

- It looks at luminance only. There is **no red-flash test**, and no account of screen size or viewing distance.
- A flash is a pair of opposing changes in relative luminance of at least 0.10 where the darker state is below 0.80. It counts the most flashes within any one second, over the full frame and over every 2×2 neighbourhood of a 12×12 grid (about 2.8% of the screen each).
- A video with more than 3 flashes per second (7 or more changes within a second) is **Excluded**: it doesn't play, and the log says so with its rate (`flash excluded video=… flashes=5.0/s`).

It can miss content that a person with photosensitive epilepsy would react to, and can flag content that is fine. Don't rely on it to make video safe for someone at risk.

To play an Excluded video anyway, add its file name to `FlashOverride`. It takes effect the next time the app starts or the folder changes (adding, removing or touching a video):

```sh
defaults write com.evanscott.videowallpaper FlashOverride -array "storm.mp4"
defaults write com.evanscott.videowallpaper FlashOverride -array-add "strobe.mov"   # add another
defaults delete com.evanscott.videowallpaper FlashOverride                          # remove all overrides
```


## Rotation

Every eligible video (analysed and not Excluded) takes turns:

- **Dwell.** A video stays for at least 20 minutes of awake, unlocked time. Time asleep, locked, with the displays off or switched to another user doesn't count; time behind other windows does.
- **When it switches.** After 20 minutes, the switch waits for a moment when the wallpaper is **Unseen** (displays asleep, locked, or every display covered by opaque windows) or **Veiled** (at least 95% of every display covered by windows for 30 s, e.g. a maximised translucent terminal), and is a 5 s crossfade. If neither happens, after an hour it switches anyway while visible, with a slow 20 s crossfade.
- **What comes next.** A random video not yet played in this pass, among those within 0.08 mean luminance of the current one, so the brightness never jumps while you can see it. If no unplayed video is that close, the nearest one plays, but only while Unseen. Once every video has played, a new pass starts.
- **New and removed videos.** A video you add plays next, at the next switch point (under the same brightness rule). Deleting the video that's playing replaces it at once; the Poster covers the gap.
- **Light and Dark.** With `Mode` set to `dynamic` (the default when the appearance is Auto), Dark prefers the darker half of your videos by median luminance and Light the brighter half. An appearance change switches at the next Unseen or Veiled moment, not in front of you. With fewer than 4 videos `dynamic` plays them all; once the matching half has all played, it replays from that half.
- **Low Power Mode** shows the Poster and doesn't switch; a deleted video is still replaced when it ends.

Each switch is logged with its reason, the videos, the luminance difference and the fade: `[rotation] switch reason=dwell on=visibility from=lucyna.mp4 to=maomao.mp4 ΔL=0.016 fade=5s visibility=unseen …`. A switch that needs Unseen logs `waiting for Unseen` once.

A video far from the others in brightness (a very dark one among bright ones) is only reached or left while Unseen, e.g. when you lock the Mac or the displays sleep.

## Settings

Preferences live in the `com.evanscott.videowallpaper` domain. `Mode` is read at every decision, so no restart is needed; a `FlashOverride` edit takes effect at the next launch or folder change.

| Key | Values | Default |
|---|---|---|
| `Mode` | `all`, `light` (brighter half), `dark` (darker half), `dynamic` (follows the appearance) | `dynamic` when the appearance is Auto, otherwise `all` |
| `FlashOverride` | Array of file names to play even though they flash (see above) | none |

```sh
defaults write com.evanscott.videowallpaper Mode -string dynamic
defaults write com.evanscott.videowallpaper Mode -string all
defaults delete com.evanscott.videowallpaper Mode          # back to the default
defaults write com.evanscott.videowallpaper FlashOverride -array "storm.mp4"
defaults read com.evanscott.videowallpaper                 # show the current settings
```

A new `Mode` takes effect at the next decision (within 5 s): a video outside the chosen half is replaced at the next Unseen or Veiled moment. The app reads, but never changes, the system's Auto appearance setting.

## Desktop picture

When the video changes, its Poster becomes the system desktop picture on every display, so the Lock screen and Mission Control match the wallpaper. macOS only lets an app set the picture of the **current Space**: other Spaces keep their own picture, and restore likewise only affects the current Space. If you use several Spaces, switch to each one and run the restore command (with the app stopped), or set the picture in System Settings.

Restore only touches displays that show one of the app's Posters; a picture you chose yourself since installing is left alone. A display with no recorded original gets another display's original, or the macOS default picture if none was recorded (for example, an install that predates recording).

## Uninstall

`make uninstall`:

1. stops the LaunchAgent, so the app can't set its Poster again;
2. restores your original desktop picture (current Space only, as above);
3. removes the app, the LaunchAgent, `~/Library/Application Support/VideoWallpaper/` and the `com.evanscott.videowallpaper` preferences, plus any legacy `.poster.jpg` in the video folder.

Your videos in `~/Movies/LiveWallpaper/` and the log in `~/Library/Logs/` are left in place.

## Design notes

Why switches wait for Unseen or Veiled moments and stay within a brightness band:

- **Abrupt luminance changes capture attention.** A sudden change in brightness pulls attention to it automatically, whatever you're doing (Yantis & Jonides, 1984, "Abrupt visual onsets and selective attention"). A dark-to-bright cut behind your work is exactly that, so large brightness jumps only happen while nobody can see the wallpaper.
- **Gradual changes go unnoticed.** Changes that happen slowly enough are often missed altogether (Simons, Franconeri & Reimer, 2000, "Change blindness in the absence of a visual disruption"). Every switch is a crossfade, 5 s when the wallpaper is covered and 20 s in the rare visible fallback, between videos of similar mean luminance.
- **Interruptions cost less at breakpoints.** Interrupting someone between tasks costs less than in the middle of one (Iqbal & Bailey, 2008, "Effects of intelligent notification management on users and their tasks"). Locking the Mac, the displays sleeping, or covering the desktop are natural breakpoints, so the Rotation prefers them, with a 20-minute minimum Dwell so the desktop feels settled rather than restless.
- **Flashing.** The flash screener follows the WCAG 2.3.1 three-flashes-per-second general threshold, approximately (see above).

## How it works

A small Swift app opens one borderless `NSWindow` per screen at desktop level (behind icons). One shared `AVQueuePlayer` + `AVPlayerLooper` drives every screen, with `videoGravity = .resizeAspectFill` to fill it and the Poster drawn underneath, so a failed player shows the Poster rather than black. It uses hardware decoding, pauses when the screens sleep or every window is covered, shows only the Poster in Low Power Mode, recovers a failed or stuck player on its own, and rebuilds windows when monitors are connected or removed. To measure videos yourself without installing anything, run `make smoke`, then `.build/smoke ~/Movies/LiveWallpaper/*.mp4` (read only).
