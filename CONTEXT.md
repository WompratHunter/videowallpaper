# VideoWallpaper

A desktop that plays a looping video behind your icons and never shows black.

## Language

**Live wallpaper**:
The video playing behind the desktop icons on every display.
_Avoid_: background, screensaver

**Wallpaper folder**:
The single folder whose videos feed the Live wallpaper; adding or removing a file there is the only user action.

**Current video**:
The video the Live wallpaper is showing right now; every display shows the same one.

**Poster**:
A still frame representing a video, shown whenever the video can't play and used as the system desktop picture (Lock screen, Mission Control).
_Avoid_: thumbnail, screensaver frame

**Rotation**:
Moving through every eligible video in the Wallpaper folder, one at a time.

**Pass**:
One trip through the Rotation in which no video repeats.

**Dwell**:
Awake, unlocked time the Current video has been showing; a switch is only considered once Dwell reaches its minimum.

**Unseen**:
Nobody can see the Live wallpaper: screens asleep, session locked, session inactive (e.g. fast user switching), or every wallpaper window fully covered by opaque windows.

**Veiled**:
The Live wallpaper is technically visible but almost entirely covered, typically by a translucent window.

**Visible**:
Neither Unseen nor Veiled.

**Analysis**:
The one-time measurement of a video's brightness and flash rate, plus its Poster, done when the video first appears.

**Excluded**:
A video left out of the Rotation because its flash rate is unsafe, unless the user overrides it.

**Recovery**:
Replacing a failed or stuck player so the Live wallpaper resumes without user action.
_Avoid_: restart (the app process does not restart)

**Lock screen**:
The macOS screen shown on wake before unlocking; it displays the Poster, not the Live wallpaper.

## Relationships

- The **Wallpaper folder** holds many videos; the **Rotation** is the eligible (non-**Excluded**) subset.
- Each video has exactly one **Poster** and one **Analysis**.
- Switching the **Current video** depends on **Dwell** and on whether the desktop is **Unseen**, **Veiled** or **Visible**.

## Flagged ambiguities

- "Screensaver" was used for what is actually the **Lock screen**.
- **Dwell** was first defined as visible-only time; redefined as awake, unlocked time so the Rotation still advances behind a translucent terminal.
