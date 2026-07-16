# m8c 2.2.3 for TrimUI Brick / Knulli — release r1

First hardware-verified SDL3 release for TrimUI Brick.

## Included

- upstream m8c `2.2.3` and bundled SDL `3.2.20`;
- completed `320x240` software surface presented through a custom Linux fbdev bridge;
- no `SDL_RenderReadPixels` and no direct drawing into the live scanout buffer;
- dedicated M8 USB-audio pump thread with cold-start recovery;
- verified raw Brick controls with selectable Face and Classic layouts;
- temporary selectable CPU cap with automatic restoration;
- optional suspend/autosave protection with timestamped backups;
- checksum-verified one-command installer;
- migration from the former `m8c-223-fb-test` development port;
- separate `m8c-223` Ports entry that leaves the original port untouched.

## Verified on

- TrimUI Brick
- Knulli Scarab `2026/05/11`
- Teensy 4.1
- M8 Headless firmware `6.5.2`

The older broken `m8c-v2.2.3-brick-r3` release is removed when this release is published.
