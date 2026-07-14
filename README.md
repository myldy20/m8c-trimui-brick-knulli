# m8c for TrimUI Brick / Knulli

Automated ARM64 builds of [laamaa/m8c](https://github.com/laamaa/m8c) for the TrimUI Brick running Knulli.

This repository does **not** contain M8 Headless firmware. It builds the client application that displays and controls a Dirtywave M8 or a Teensy running M8 Headless firmware.

## What a release contains

- `m8c-bin` built for Linux `aarch64`
- a private copy of SDL3 in `lib/`
- `install.sh`, which installs the client beside an existing m8c installation
- a separate `m8c-v2.sh` launcher
- the upstream controller database and license files

The installer does not overwrite the existing client. It creates:

```text
/userdata/roms/ports/m8c-v2/
/userdata/roms/ports/m8c-v2.sh
```

The original installation remains at:

```text
/userdata/roms/ports/m8c/
/userdata/roms/ports/m8c.sh
```

## Installation on Knulli

Download the latest release archive and copy it to the Brick. Then run over SSH:

```sh
cd /userdata/system
unzip m8c-trimui-brick-knulli-*.zip
cd m8c-trimui-brick-knulli-*
sh install.sh
```

Refresh the Ports list or restart EmulationStation. A separate `m8c-v2` entry should appear.

## Removal

```sh
rm -rf /userdata/roms/ports/m8c-v2
rm -f /userdata/roms/ports/m8c-v2.sh
```

## Building a newer upstream version

Open **Actions → Build ARM64 release → Run workflow**, enter the upstream m8c version, and run it. The workflow creates both an artifact and, when requested, a GitHub Release.

## Compatibility approach

The build targets an older Linux userspace (`Debian 11 / glibc 2.31`) to improve compatibility with embedded distributions. SDL3 is bundled locally; Knulli still supplies common system libraries such as libc, libm, libdrm, libgbm, EGL/GLES, ALSA, udev and libserialport.

Tested hardware and firmware combinations should be documented in Issues or release notes.

## Credits and licensing

- m8c: Copyright Jonne Kokkonen and contributors, MIT License
- SDL3: Copyright SDL contributors, zlib License
- Original TrimUI Brick/Knulli port: [f32-0/m8c-brick-knulli](https://github.com/f32-0/m8c-brick-knulli)

This repository contains build and packaging scripts only. Upstream source code is downloaded during GitHub Actions builds.
