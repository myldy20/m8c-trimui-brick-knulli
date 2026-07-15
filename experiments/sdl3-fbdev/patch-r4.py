#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-r4.py PATH_TO_M8C_SOURCE")

root = pathlib.Path(sys.argv[1])


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"{description}: anchor not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


render = root / "src" / "render.c"

# r2 rendered a full 1024x768 offscreen frame, read it back, then copied it to
# fb0. Render only at the native M8 resolution and let the bridge perform one
# optimized nearest-neighbour expansion into the current fbdev scanout page.
replace_once(
    render,
    '''  SDL_SetHint(SDL_HINT_RENDER_DRIVER, "software");
  const int output_width = fb_bridge_width();
  const int output_height = fb_bridge_height();
''',
    '''  SDL_SetHint(SDL_HINT_RENDER_DRIVER, "software");
  conf->integer_scaling = 1;
''',
    "remove full-frame output dimensions",
)

replace_once(
    render,
    '''  if (!SDL_CreateWindowAndRenderer("M8C", output_width, output_height, 0, &win, &rend)) {
''',
    '''  if (!SDL_CreateWindowAndRenderer("M8C", texture_width, texture_height, 0, &win, &rend)) {
''',
    "create native-resolution offscreen renderer",
)

# Remove r2's temporary per-button diagnostics while keeping its state
# deduplication and Select+configured-quit handling.
input_c = root / "src" / "input.c"
text = input_c.read_text(encoding="utf-8")
text, count = re.subn(
    r'''\n  if \(pressed\) \{\n    SDL_LogInfo\(SDL_LOG_CATEGORY_INPUT, "Brick gamepad button down: %d state=0x%02X", button,\n                gamepad_state.current_buttons\);\n  \}\n''',
    '\n',
    text,
    count=1,
)
if count != 1:
    raise SystemExit("remove r2 button diagnostics: anchor not found")
input_c.write_text(text, encoding="utf-8")

# 60 Hz is sufficient for the M8 display and avoids asking the A133 to perform
# up to 120 readback-and-scale passes per second during rapid navigation.
main_c = root / "src" / "main.c"
replace_once(
    main_c,
    '''  // Process the application's main callback roughly at 120 Hz
  SDL_SetHint(SDL_HINT_MAIN_CALLBACK_RATE, "120");
''',
    '''  // Brick fbdev bridge: process display and input at roughly 60 Hz.
  SDL_SetHint(SDL_HINT_MAIN_CALLBACK_RATE, "60");
''',
    "cap callback rate",
)

print("Applied r4 native-resolution bridge patches")
