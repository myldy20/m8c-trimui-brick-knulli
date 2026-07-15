#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: prepare-build-r2.py PATH_TO_BUILD_SH")

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
original = text


def replace_once(old: str, new: str, description: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f"{description}: anchor not found")
    text = text.replace(old, new, 1)


replace_once(
    'PACKAGE_REVISION="${PACKAGE_REVISION:-1}"',
    'PACKAGE_REVISION="${PACKAGE_REVISION:-2}"',
    "package revision",
)

replace_once(
    'python3 /work/experiments/sdl3-fbdev/patch-m8c.py m8c/src/render.c\n',
    '''python3 /work/experiments/sdl3-fbdev/patch-m8c.py m8c/src/render.c
cp /work/experiments/sdl3-fbdev/audio_sdl_brick.c m8c/src/backends/audio_sdl.c
python3 /work/experiments/sdl3-fbdev/patch-r2.py m8c
''',
    "r2 source patches",
)

replace_once(
    'make -j"$(nproc)"',
    'make CFLAGS="-DBRICK_GAMEPAD_ONLY" -j"$(nproc)"',
    "Brick compile flag",
)

replace_once(
    'cp "$ORIGINAL_CONFIG" "$APP_DIR/m8c/config.ini"\n',
    '''cp "$ORIGINAL_CONFIG" "$APP_DIR/m8c/config.ini"
# SDL3 reports the Brick d-pad as digital buttons and analog axes. Disable the
# legacy axis aliases in this device-specific package to avoid repeated moves.
sed -i \
    -e 's/^gamepad_analog_axis_updown=.*/gamepad_analog_axis_updown=-1/' \
    -e 's/^gamepad_analog_axis_leftright=.*/gamepad_analog_axis_leftright=-1/' \
    "$APP_DIR/m8c/config.ini"
''',
    "Brick control config",
)

replace_once(
    'export SDL_RENDER_VSYNC="0"\n',
    '''export SDL_RENDER_VSYNC="0"
export SDL_AUDIODRIVER="alsa"
''',
    "ALSA selection",
)

replace_once(
    '    echo "SDL_RENDER_DRIVER=$SDL_RENDER_DRIVER"\n',
    '''    echo "SDL_RENDER_DRIVER=$SDL_RENDER_DRIVER"
    echo "SDL_AUDIODRIVER=$SDL_AUDIODRIVER"
''',
    "launcher audio proof",
)

replace_once(
    'framebuffer=/dev/fb0\n',
    '''framebuffer=/dev/fb0
framebuffer_clear_before_copy=false
input_mode=gamepad-only
analog_dpad_aliases=false
audio_pump=recording-callback-to-playback
exit_fallback=select-plus-start
''',
    "version metadata",
)

if text == original:
    raise SystemExit("prepare-build-r2 made no changes")

path.write_text(text, encoding="utf-8")
print("Prepared SDL3 fbdev r2 build script")
