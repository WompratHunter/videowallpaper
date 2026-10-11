# VideoWallpaper

A desktop that plays a looping video behind your icons and never shows black.

## Language

**Live wallpaper**:
The video playing behind the desktop icons on every display.
_Avoid_: background, screensaver

**Wallpaper folder**:
The single folder whose videos feed the Live wallpaper; adding or removing a file there is the only user action.

**Video**:
A file in the Wallpaper folder, known by its file name; renaming a file makes a new Video.
_Avoid_: clip, file (when meaning the Video)

**Version**:
One particular content of a Video, told apart by its size and modification time; replacing a file under the same name gives the Video a new Version.

**Current video**:
The video the Live wallpaper is showing right now; every display shows the same one.

**Poster**:
A still frame representing a Version of a Video, shown whenever the video can't play and used as the system desktop picture (Lock screen, Mission Control).
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

**Presence**:
Whether anyone can see the Live wallpaper right now: Unseen, Veiled or Visible.
_Avoid_: visibility (as a noun for the three states)

**Analysis**:
The one-time measurement of a Version's brightness and flash rate, plus its Poster, done when the Version first appears.

**Excluded**:
A video left out of the Rotation because its flash rate is unsafe, unless the user overrides it.

**Recovery**:
Replacing a failed or stuck player so the Live wallpaper resumes without user action.
_Avoid_: restart (the app process does not restart)

**Mode**:
The user's choice of which videos the Rotation favours: all of them, the darker half, the brighter half, or dynamic (following Daylight). "Light" and "dark" name halves of the videos by brightness, not the system appearance.

**Playback state**:
What the Live wallpaper is doing on purpose: playing, paused because nobody can see it, or showing only the Poster in Low Power Mode. Recovery is separate: it is what happens when playback fails against this intent.
_Avoid_: mode (for these states)

**Low Power Mode**:
The macOS power-saving setting; the Live wallpaper shows only the Poster while it is on, and no Analysis runs.
_Avoid_: power saving, "Mode" on its own

**Lock screen**:
The macOS screen shown on wake before unlocking; it displays the Poster, not the Live wallpaper.

**Daylight**:
How bright it is outdoors where the Mac is right now, from full night to full day; for now it comes from the sun's position only.
_Avoid_: ambient light (that is the room, not the sky), weather, lighting conditions

**Target brightness**:
The place in the Rotation's dark-to-bright ranking that the next pick aims for, set by Daylight: night aims at the darkest videos, midday at the brightest.

## Relationships

- The **Wallpaper folder** holds many videos; the **Rotation** is the eligible (non-**Excluded**) subset.
- A **Video** has one or more **Versions** over time, but only its latest is in the Wallpaper folder; each **Version** has exactly one **Poster** and one **Analysis**.
- Pass history and the user's flash override belong to the **Video**, so they survive a new **Version** but not a rename.
- Switching the **Current video** depends on **Dwell** and on **Presence** (**Unseen**, **Veiled** or **Visible**).
- **Daylight** sets the **Target brightness**; the **Rotation** picks near it. A Current video far from the Target brightness makes a switch due early, but only at an **Unseen** or **Veiled** moment.

## Flagged ambiguities

- "Screensaver" was used for what is actually the **Lock screen**.
- "Mode" was used for three things: the user's **Mode**, the **Playback state** and **Low Power Mode**. Only the first is "Mode".
- "Lighting conditions" meant outdoor **Daylight**, not the room's light measured by the Mac's ambient light sensor.
- **Dwell** was first defined as visible-only time; redefined as awake, unlocked time so the Rotation still advances behind a translucent terminal.
