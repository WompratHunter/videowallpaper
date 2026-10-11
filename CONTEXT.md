# VideoWallpaper

A desktop that plays a looping video behind your icons and never shows black.

## Language

**Live wallpaper**:
The video playing behind the desktop icons on every display.
_Avoid_: background, screensaver

**Wallpaper folder**:
The single folder, chosen by the user, whose videos feed the Live wallpaper.

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

**Enabled**:
The Live wallpaper is on: windows show the Current video or its Poster, and the Poster is the system desktop picture.

**Disabled**:
The Live wallpaper is off and the user's own desktop picture is back on every screen; quitting the app disables it.
_Avoid_: paused (that is a Playback state while Enabled), stopped

**Launch at login**:
Whether the app starts when the user logs in; changing it takes effect at the next login and never starts or stops the running app.
_Avoid_: login item, autostart

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
- Whenever the app is **Disabled**, the user's own desktop picture shows; the **Poster** is the desktop picture only while **Enabled**.
- Pass history and the user's flash override belong to the **Video**, so they survive a new **Version** but not a rename.
- Switching the **Current video** depends on **Dwell** and on **Presence** (**Unseen**, **Veiled** or **Visible**).
- **Daylight** sets the **Target brightness**; the **Rotation** picks near it. A Current video far from the Target brightness makes a switch due early, but only at an **Unseen** or **Veiled** moment.

## Flagged ambiguities

- The **Wallpaper folder** was first fixed, and dropping files was "the only user action"; the user now also chooses the folder, the **Mode**, flash overrides and whether the app is **Enabled**.
- "Screensaver" was used for what is actually the **Lock screen**.
- "Mode" was used for three things: the user's **Mode**, the **Playback state** and **Low Power Mode**. Only the first is "Mode".
- "Lighting conditions" meant outdoor **Daylight**, not the room's light measured by the Mac's ambient light sensor.
- **Dwell** was first defined as visible-only time; redefined as awake, unlocked time so the Rotation still advances behind a translucent terminal.
