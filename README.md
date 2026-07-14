# m8c for TrimUI Brick / Knulli

A current ARM64 build of [m8c](https://github.com/laamaa/m8c) for running a Dirtywave M8 or a Teensy with M8 Headless firmware from a TrimUI Brick.

The original Brick port made this setup possible. This project keeps the same simple Ports experience, but builds a newer m8c with SDL3 and packages everything needed for Knulli.

> This is the **m8c client**, not M8 Headless firmware for the Teensy.

## What is included

- m8c built for Linux `aarch64`
- a private SDL3 runtime, kept inside the port directory
- the Knulli `cdc-acm.ko` module and a ready-to-use configuration
- a launcher that lowers the Brick CPU limit while m8c is open
- an optional suspend/autosave patch for M8 Headless
- two switchable control profiles
- both SSH and SD-card installation methods

The current package has been tested on a TrimUI Brick running Knulli Scarab `2026/05/11`, with a Teensy 4.1 running M8 Headless `6.5.2`.

## Installation option 1: one command over SSH

Connect to the Brick:

```sh
ssh root@BRICK_IP
```

Then run:

```sh
curl -fsSL https://raw.githubusercontent.com/myldy20/m8c-trimui-brick-knulli/main/install.sh | sh
```

The installer downloads the latest release, verifies its SHA-256 checksum and installs the `m8c` entry under Ports. When upgrading an existing installation, it saves a backup under:

```text
/userdata/system/backups/m8c/
```

During installation it asks whether to enable the optional suspend/autosave patch described below.

For a fully non-interactive install with suspend autosave protection and the **Face Buttons** control profile:

```sh
curl -fsSL https://raw.githubusercontent.com/myldy20/m8c-trimui-brick-knulli/main/install.sh | M8C_SLEEP_PATCH=yes M8C_CONTROL_PROFILE=face-buttons sh
```

The available control-profile values are:

- `keep` — keep the existing configuration when upgrading; this is the default
- `original` — apply the Original Brick profile
- `face-buttons` — apply the Face Buttons profile

For a non-interactive install with the suspend patch but without forcing a control profile:

```sh
curl -fsSL https://raw.githubusercontent.com/myldy20/m8c-trimui-brick-knulli/main/install.sh | M8C_SLEEP_PATCH=yes sh
```

Or without the suspend patch:

```sh
curl -fsSL https://raw.githubusercontent.com/myldy20/m8c-trimui-brick-knulli/main/install.sh | M8C_SLEEP_PATCH=no sh
```

Refresh the Ports list or restart EmulationStation after installation.

## Installation option 2: copy the files to the SD card

1. Download the latest release ZIP.
2. Extract it on your computer.
3. Open the extracted `roms/ports/` directory.
4. Copy its contents to `SHARE/roms/ports/` on the Knulli SD card.
5. Put the card back into the Brick and refresh Ports or reboot.

The archive already contains this layout:

```text
roms/ports/
├── m8c.sh
└── m8c/
    ├── m8c-bin
    ├── cdc-acm.ko
    ├── lib/
    │   └── libSDL3.so.0
    ├── m8c/
    │   ├── config.ini
    │   └── gamecontrollerdb.txt
    └── tools/
        ├── patch-suspend.sh
        └── set-controls.sh
```

Copying the precompiled files manually does **not** change Knulli suspend behaviour. The optional patch can be enabled later over SSH:

```sh
sh /userdata/roms/ports/m8c/tools/patch-suspend.sh install
```

## CPU frequency behaviour

The launcher temporarily limits the Brick CPU maximum frequency to **816 MHz** while m8c is running. m8c does not need the full 1.4 GHz available to most emulators, so this reduces heat and unnecessary power use.

The previous CPU limit is restored when m8c exits normally. A reboot also restores the normal kernel CPU policy. After a forced power-off or `kill -9`, the lower limit may remain active until the next reboot because the launcher does not get a chance to run its cleanup handler.

## Suspend and wake-up

Knulli may remove USB host power immediately when the Brick enters suspend. With M8 Headless this can interrupt the Teensy before it has had time to disconnect and autosave.

The optional suspend patch changes `/usr/bin/knulli-suspend` so that, while m8c is open, it:

1. sends the M8 disconnect command;
2. waits one second for autosave;
3. continues with the normal Knulli suspend process.

Enable it:

```sh
sh /userdata/roms/ports/m8c/tools/patch-suspend.sh install
```

Check its state:

```sh
sh /userdata/roms/ports/m8c/tools/patch-suspend.sh status
```

Remove it:

```sh
sh /userdata/roms/ports/m8c/tools/patch-suspend.sh remove
```

A backup of `knulli-suspend` is written to `/userdata/system/backups/m8c/` whenever the patch is added or removed. A Knulli system update may replace the patched file, in which case the patch needs to be applied again.

After wake-up, USB, M8 Headless and sometimes Wi-Fi can take several seconds to return. This delay comes from the Brick/Knulli device drivers rather than m8c. If the M8 screen does not reconnect after waiting, exit and reopen m8c.

## Controls

A fresh installation uses the **Original Brick** profile from the first TrimUI Brick port. Upgrading through the SSH installer preserves the existing `config.ini`, including any control changes already made by the user.

### Original Brick profile

| Brick control | M8 action |
|---|---|
| D-pad | Up / Down / Left / Right |
| Select | Shift |
| Start | Play |
| B | Edit |
| A | Options |
| Select + Y | Exit m8c |

Apply it:

```sh
sh /userdata/roms/ports/m8c/tools/set-controls.sh original
```

### Face Buttons profile

This profile puts the four main M8 controls on the four face buttons.

| Brick control | M8 action |
|---|---|
| D-pad | Up / Down / Left / Right |
| X | Shift |
| Y | Play |
| B | Edit |
| A | Options |
| Select + Y | Exit m8c |

`Y` by itself starts or stops playback. Holding `Select` and pressing `Y` exits the application.

Apply it:

```sh
sh /userdata/roms/ports/m8c/tools/set-controls.sh face-buttons
```

Check the currently detected profile:

```sh
sh /userdata/roms/ports/m8c/tools/set-controls.sh status
```

Exit m8c before switching profiles. The tool changes only the four main gamepad assignments, leaving graphics, audio and other settings untouched. Before each change it saves the current configuration under:

```text
/userdata/system/backups/m8c/controls/
```

## Updating

Run the one-command installer again, or copy a newer release over `SHARE/roms/ports/`. The SSH installer keeps the previous installation as a timestamped backup and preserves the existing `config.ini` where possible.

## Building a newer m8c release

Open **Actions → Build ARM64 release → Run workflow**, enter the desired upstream m8c version and run the workflow. It builds inside a disposable Debian ARM64 container and can publish the resulting ZIP as a GitHub Release.

The package targets an older Linux userspace (`Debian 11 / glibc 2.31`) for compatibility with embedded distributions. SDL3 is bundled with the port; Knulli supplies the remaining common system libraries.

## Credits

- [laamaa/m8c](https://github.com/laamaa/m8c) — the m8c client
- [Dirtywave/M8HeadlessFirmware](https://github.com/Dirtywave/M8HeadlessFirmware) — M8 Headless firmware
- [f32-0/m8c-brick-knulli](https://github.com/f32-0/m8c-brick-knulli) — the original TrimUI Brick/Knulli port
- SDL contributors — SDL3

m8c is MIT-licensed. SDL3 uses the zlib license. The build and packaging scripts in this repository are MIT-licensed.
