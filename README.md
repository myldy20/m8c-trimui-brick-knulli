# m8c 2.2.3 for TrimUI Brick / Knulli

An ARM64 port of [m8c](https://github.com/laamaa/m8c) for running a Dirtywave M8 or a Teensy 4.1 with M8 Headless firmware from a TrimUI Brick.

This repository contains the **m8c client**, not the M8 Headless firmware.

## Tested hardware

- TrimUI Brick (`sun50iw10`, aarch64)
- Knulli Scarab `2026/05/11`
- Teensy 4.1
- M8 Headless firmware `6.5.2`
- upstream m8c `2.2.3`
- SDL `3.2.20`

The release installs as a separate Ports entry named `m8c-223`. It does not overwrite the original `m8c` Brick port.

## One-command installation

Connect to the Brick over SSH and run:

```sh
curl -fsSL https://raw.githubusercontent.com/myldy20/m8c-trimui-brick-knulli/main/install.sh | sh
```

The installer verifies the release checksum and asks for:

1. CPU limit while m8c is open;
2. suspend/autosave protection;
3. control layout.

Refresh Ports or reboot after installation.

### Non-interactive installation

```sh
curl -fsSL https://raw.githubusercontent.com/myldy20/m8c-trimui-brick-knulli/main/install.sh |
  M8C_CPU_LIMIT=1008 M8C_AUTOSAVE=yes M8C_LAYOUT=face sh
```

Accepted values:

- `M8C_CPU_LIMIT`: `system`, `816`, `1008`, `1200`, `1416`, `keep`
- `M8C_AUTOSAVE`: `yes`, `no`, `keep`
- `M8C_LAYOUT`: `face`, `classic`, `keep`

The default fresh-install profile is `1008 MHz`, autosave chosen interactively, and the `face` layout.

## Manual SD-card installation

Download `m8c-trimui-brick-knulli.zip` from the latest release and extract it. Copy the contents of its `roms/ports/` directory into Knulli's `SHARE/roms/ports/` directory.

Manual copying installs the default settings but does not patch Knulli suspend. Configure the port afterwards over SSH:

```sh
sh /userdata/roms/ports/m8c-223/tools/configure.sh \
  --cpu 1008 \
  --layout face \
  --autosave yes
```

## Controls

Knulli's semantic SDL mapping for the Brick is incorrect, so the port reads verified raw joystick codes.

### Face layout

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

### Classic layout

| Brick control | M8 action |
|---|---|
| D-pad | Navigate |
| A | Option |
| B | Edit |
| Select | Shift |
| Start | Play |
| X / Y | Unused |
| Select + Y | Exit m8c |

Change settings later with:

```sh
sh /userdata/roms/ports/m8c-223/tools/configure.sh \
  --cpu 816 \
  --layout classic \
  --autosave yes
```

Show current settings:

```sh
sh /userdata/roms/ports/m8c-223/tools/configure.sh status
```

## CPU limit

The launcher can temporarily lower `scaling_max_freq` while m8c is running and restores every previous value on exit. `1008 MHz` is the default balance; `816 MHz` reduces heat and battery use further.

A forced `kill -9` prevents the launcher cleanup trap from running. Rebooting restores the normal Knulli CPU policy.

## Suspend/autosave protection

Knulli may remove USB power immediately during suspend. The optional patch adds a small guarded block to `/usr/bin/knulli-suspend`: when `m8c-bin` is running, it sends `SIGTERM`, waits one second for m8c to disconnect the M8 and allow Headless autosave, then continues the normal suspend script.

Every change creates a timestamped backup under:

```text
/userdata/system/backups/m8c/suspend/
```

A Knulli system update may replace the patched script. Run the installer or the configuration command again after an update.

## Video and audio implementation

The Brick does not expose a normal DRM/KMS display suitable for generic SDL3. The port therefore:

1. renders a completed `320x240` ARGB8888 frame in memory;
2. expands that frame to the active `1024x768` Linux framebuffer page;
3. avoids `SDL_RenderReadPixels` and avoids drawing directly into the live scanout buffer.

Direct rendering into the live framebuffer was rejected during hardware testing because it exposed partially drawn frames and flickered heavily.

M8 USB audio is drained by a dedicated SDL3 pump thread. A startup watchdog restarts initially silent ALSA streams up to three times.

## Updating and backups

Run the one-command installer again. It backs up the previous `m8c-223` installation, and also migrates the former `m8c-223-fb-test` development port, under:

```text
/userdata/system/backups/m8c/releases/
```

The original `m8c` port is never modified.

## Building

The GitHub Actions workflow builds SDL3 and m8c inside a disposable Debian Bullseye ARM64 container, validates all runtime dependencies and produces:

```text
m8c-trimui-brick-knulli.zip
m8c-trimui-brick-knulli.zip.sha256
```

## Known scope

The verified target is the TrimUI Brick with M8 Headless firmware reporting the MK1-style `320x240` display. Other Knulli versions and M8 hardware models have not been verified.

## Credits

- [laamaa/m8c](https://github.com/laamaa/m8c) — upstream m8c client
- [Dirtywave/M8HeadlessFirmware](https://github.com/Dirtywave/M8HeadlessFirmware) — M8 Headless firmware
- [f32-0/m8c-brick-knulli](https://github.com/f32-0/m8c-brick-knulli) — original TrimUI Brick/Knulli port
- SDL contributors

m8c is MIT-licensed. SDL3 uses the zlib license. Repository build and packaging scripts are MIT-licensed.
