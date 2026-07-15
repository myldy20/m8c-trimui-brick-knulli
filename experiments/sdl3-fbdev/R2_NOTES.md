# SDL3 fbdev experiment: r1 device result and r2 changes

## r1 result on TrimUI Brick / Knulli Scarab 2026/05/11

The real m8c 2.2.3 binary launched with SDL 3.2.20 using the offscreen video driver and software renderer. It found the M8 Headless device, opened the controller, identified firmware 6.5.2, initialized the fbdev bridge and reached a normal shutdown after being killed remotely.

Observed problems:

- visible display flicker;
- a single d-pad press could move two or three rows;
- no audible output despite successful SDL3 audio-device initialization;
- the normal gamepad exit combination was not reliable.

## r2 changes

- Do not clear the visible framebuffer before each frame copy.
- Refresh fbdev x/y offsets before copying a frame.
- Ignore evmapy's duplicate virtual-keyboard events and use the physical SDL gamepad only.
- Disable legacy analog-axis d-pad aliases in the packaged config.
- Accept Select+Start as a Brick-specific exit fallback and log button-down codes.
- Replace the upstream output-driven SDL3 audio pump with a recording-callback pump that queues captured M8 samples into the playback stream.
- Log the SDL3 audio driver and every enumerated recording/playback device at info level.

The r2 package remains a separate `m8c-223-fb-test` entry and must not replace the working original or SDL2 baseline ports.
