# m8c 2.2.3 for TrimUI Brick / Knulli

A device-specific ARM64 port of [m8c](https://github.com/laamaa/m8c) for using a Dirtywave M8 or Teensy 4.1 with M8 Headless firmware from a TrimUI Brick.

> This repository contains the **m8c client**, not M8 Headless firmware for the Teensy.

## Project status

The current development build is working on real hardware, but the new SDL3 port has not yet been published as a normal GitHub Release.

Verified setup:

- TrimUI Brick (`sun50iw10`, aarch64)
- Knulli Scarab `2026/05/11`
- Teensy 4.1
- M8 Headless firmware `6.5.2`
- upstream m8c `2.2.3`
- SDL `3.2.20`

Working:

- M8 display on the Brick screen
- USB serial connection and reconnect after normal startup
- M8 USB audio routed to the Brick speaker
- D-pad and all four face buttons
- clean application exit and M8 disconnect

Still being tuned:

- display latency/smoothness compared with the original SDL2 Brick port
- suspend/autosave integration
- final release packaging and one-command installer

**Do not use the older `m8c-v2.2.3-brick-r3` release on Knulli Scarab.** That release used generic SDL3 video backends and fails on the Brick with `No available video device`. The tested port lives in draft PR #2 until the final device check is complete.

## Why a custom video path is required

The Brick does not expose a normal DRM/KMS display suitable for generic SDL3. Knulli's system SDL2 contains a vendor PowerVR backend (`MALI_CreateWindow`), which is why the original SDL2 port works smoothly.

The current SDL3 port therefore uses:

1. SDL3's offscreen software renderer;
2. a native `320x240` M8 frame;
3. a custom Linux fbdev bridge;
4. nearest-neighbour row expansion into the active `1024x768` framebuffer page.

An attempted direct software renderer into live framebuffer memory was rejected because the display exposed partially drawn frames and flickered heavily. The working approach keeps rendering offscreen and presents completed frames only.

## Controls

The Knulli/SDL semantic gamepad mapping for the Brick is incorrect, so the port reads verified raw joystick button numbers directly.

| Brick control | M8 action |
|---|---|
| D-pad | Navigate |
| A | Play |
| B | Shift |
| X | Edit |
| Y | Option |
| Select | Exit modifier only |
| Start | Unused |
| Select + B | Exit m8c |

L1, R1, L2, R2 and the volume buttons are ignored by m8c. The volume buttons remain available to Knulli.

Verified raw input map:

```text
B=0 A=1 X=2 Y=3 L1=4 R1=5 L2=6 R2=7 Select=8 Start=9
D-pad=hat0
GUID=03006aae5e0400008e02000014010000
```

## Audio

SDL3 enumerates the M8 as `M8:USB Audio`. A dedicated audio pump thread continuously drains the recording stream and feeds the Brick playback stream. This replaced an earlier callback-based bridge that eventually produced ALSA capture overruns.

## Building the current candidate

Open:

```text
Actions → Build SDL3 fbdev experiment → Run workflow
```

The workflow builds inside a disposable Debian Bullseye ARM64 container and uploads a non-destructive test package named like:

```text
m8c-223-fb-test-r8
```

The package installs as a separate Ports entry:

```text
m8c-223-fb-test
```

It does not overwrite the original `m8c` port or the SDL2 baseline test.

## Development history

The implementation and the failed approaches are retained under:

```text
experiments/sdl3-fbdev/
```

Important milestones:

- SDL2 baseline: proved that Knulli's patched system SDL2 works with the Brick display.
- r1: first real m8c 2.2.3 image through SDL3 offscreen + fbdev.
- r2: removed framebuffer clearing, fixed duplicate D-pad events and restored audio.
- r3: direct live-framebuffer rendering; rejected because of severe flicker and latency.
- r4: native-resolution readback and row expansion; first acceptably responsive display.
- r5/r6: audio pump thread and exact raw-input diagnostics.
- r7: fully working controls from raw joystick events.
- r8: final control layout and restored upstream 120 Hz callback rate for lower latency.

## Repository branches and pull requests

- PR #2 — current SDL3/fbdev port; draft until r8 is tested on the device.
- PR #1 — successful pre-SDL3/SDL2 baseline retained for reference.

## Credits

- [laamaa/m8c](https://github.com/laamaa/m8c) — upstream m8c client
- [Dirtywave/M8HeadlessFirmware](https://github.com/Dirtywave/M8HeadlessFirmware) — M8 Headless firmware
- [f32-0/m8c-brick-knulli](https://github.com/f32-0/m8c-brick-knulli) — original TrimUI Brick/Knulli port
- SDL contributors

m8c is MIT-licensed. SDL3 uses the zlib license. Repository build and packaging scripts are MIT-licensed.
