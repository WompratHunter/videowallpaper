# videowallpaper

Native macOS video wallpaper. No third-party app — just AVFoundation, compiled once with the system Swift compiler.

Plays any `.mp4`, `.mov` or `.m4v` from `~/Movies/LiveWallpaper/`. Drop in a new file and, once it has been analysed (a few seconds), it switches automatically.

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
| Change wallpaper | Drop a `.mp4` into `~/Movies/LiveWallpaper/` |
| Stop | `launchctl unload ~/Library/LaunchAgents/com.videowallpaper.plist` |
| Start | `launchctl load ~/Library/LaunchAgents/com.videowallpaper.plist` |
| Restore original desktop picture | Stop, then `~/Applications/VideoWallpaper.app/Contents/MacOS/videowallpaper --restore-wallpaper` |
| Uninstall | `make uninstall` |
| Logs | `tail -f ~/Library/Logs/videowallpaper.log` (launch, wake and unlock lines include player state) |
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

Until rotation arrives, the newest *eligible* video (analysed and not Excluded) plays.

## Desktop picture

When the video changes, its Poster becomes the system desktop picture on every display, so the Lock screen and Mission Control match the wallpaper. macOS only lets an app set the picture of the **current Space**: other Spaces keep their own picture, and restore likewise only affects the current Space. If you use several Spaces, switch to each one and run the restore command (with the app stopped), or set the picture in System Settings.

Restore only touches displays that show one of the app's Posters; a picture you chose yourself since installing is left alone. A display with no recorded original gets another display's original, or the macOS default picture if none was recorded (for example, an install that predates recording).

## Uninstall

`make uninstall`:

1. stops the LaunchAgent, so the app can't set its Poster again;
2. restores your original desktop picture (current Space only, as above);
3. removes the app, the LaunchAgent, `~/Library/Application Support/VideoWallpaper/` and the `com.evanscott.videowallpaper` preferences, plus any legacy `.poster.jpg` in the video folder.

Your videos in `~/Movies/LiveWallpaper/` and the log in `~/Library/Logs/` are left in place.

## How it works

A small Swift app opens one borderless `NSWindow` per screen at desktop level (behind icons). One shared `AVQueuePlayer` + `AVPlayerLooper` drives every screen, with `videoGravity = .resizeAspectFill` to fill it and the Poster drawn underneath, so a failed player shows the Poster rather than black. It uses hardware decoding, pauses when the screens sleep or every window is covered, shows only the Poster in Low Power Mode, recovers a failed or stuck player on its own, and rebuilds windows when monitors are connected or removed. To measure videos yourself without installing anything, run `make smoke`, then `.build/smoke ~/Movies/LiveWallpaper/*.mp4` (read only).
