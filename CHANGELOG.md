# m8c 2.2.3 for TrimUI Brick / Knulli — release r2

Maintenance release fixing startup on clean Knulli installations.

## Fixed

- removed the launcher's hidden dependency on PortMaster and `control.txt`;
- switched runtime path discovery to the verified Knulli location `/userdata/roms/ports/m8c-223`;
- started logging before any runtime setup, so early launcher failures are now captured;
- added on-screen startup errors instead of an unexplained black-screen exit;
- added preflight checks for the binary, bundled SDL3, kernel module and framebuffer;
- added package validation that rejects a launcher which sources PortMaster again.

## Included from r1

- upstream m8c `2.2.3` and bundled SDL `3.2.20`;
- completed `320x240` software surface presented through a custom Linux fbdev bridge;
- dedicated M8 USB-audio pump thread with cold-start recovery;
- verified raw Brick controls with selectable Face and Classic layouts;
- temporary selectable CPU cap with automatic restoration;
- optional suspend/autosave protection with timestamped backups;
- checksum-verified one-command installer;
- separate `m8c-223` Ports entry that leaves the original port untouched.

## Verified target

- TrimUI Brick
- Knulli Scarab `2026/05/11`
- Teensy 4.1
- M8 Headless firmware `6.5.2`
