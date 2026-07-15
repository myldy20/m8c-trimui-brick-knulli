#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: prepare-build-r3.py PATH_TO_BUILD_SH")

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f"{description}: anchor not found")
    text = text.replace(old, new, 1)


replace_once(
    'PACKAGE_REVISION="${PACKAGE_REVISION:-2}"',
    'PACKAGE_REVISION="${PACKAGE_REVISION:-3}"',
    "package revision",
)

replace_once(
    'python3 /work/experiments/sdl3-fbdev/patch-r2.py m8c\n',
    '''python3 /work/experiments/sdl3-fbdev/patch-r2.py m8c
cp /work/experiments/sdl3-fbdev/fb_bridge_direct.c m8c/src/fb_bridge.c
cp /work/experiments/sdl3-fbdev/fb_bridge_direct.h m8c/src/fb_bridge.h
python3 /work/experiments/sdl3-fbdev/patch-r3.py m8c
''',
    "r3 direct-render source patches",
)

replace_once(
    'framebuffer_clear_before_copy=false\n',
    '''framebuffer_clear_before_copy=false
framebuffer_mode=direct-sdl-surface
framebuffer_readback_copy=false
''',
    "direct-render metadata",
)

replace_once(
    'exit_fallback=select-plus-start\n',
    '''exit_fallback=select-plus-start
exit_axis_fallback=true
''',
    "axis exit metadata",
)

path.write_text(text, encoding="utf-8")
print("Prepared SDL3 fbdev r3 build script")
