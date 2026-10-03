# videowallpaper

Native macOS video wallpaper. No third-party app — just AVFoundation, compiled once with the system Swift compiler.

Plays any `.mp4` or `.mov` from `~/Movies/LiveWallpaper/`. Drop in a new file and it switches automatically.

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
| Uninstall | `make uninstall` |
| Logs | `tail -f ~/Library/Logs/videowallpaper.log` (launch, wake and unlock lines include player state) |
| Lint + test + compile | `make build` |

## How it works

A small Swift app opens one borderless `NSWindow` per screen at desktop level (behind icons), plays the video with `AVQueuePlayer` + `AVPlayerLooper` for seamless looping, and uses `videoGravity = .resizeAspectFill` to fill the screen. It uses hardware decoding, pauses on screen sleep, and rebuilds windows when monitors are connected or removed. A static poster frame is exported for Mission Control and the login screen.
