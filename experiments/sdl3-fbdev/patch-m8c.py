#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-m8c.py PATH_TO_RENDER_C")

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
original = text

text = text.replace(
    '#include "render.h"\n',
    '#include "render.h"\n#include "fb_bridge.h"\n',
    1,
)

text = text.replace(
    'void renderer_close(void) {\n  SDL_LogDebug(SDL_LOG_CATEGORY_RENDER, "Closing renderer");\n',
    'void renderer_close(void) {\n  SDL_LogDebug(SDL_LOG_CATEGORY_RENDER, "Closing renderer");\n  fb_bridge_close();\n',
    1,
)

init_anchor = '''  if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) == false) {
    SDL_LogCritical(SDL_LOG_CATEGORY_ERROR, "SDL_Init: %s", SDL_GetError());
    return 0;
  }
'''

init_replacement = init_anchor + '''
  if (!fb_bridge_init("/dev/fb0")) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "Failed to initialize fbdev output bridge.");
    return 0;
  }

  SDL_SetHint(SDL_HINT_RENDER_DRIVER, "software");
  const int output_width = fb_bridge_width();
  const int output_height = fb_bridge_height();
'''

if init_anchor not in text:
    raise SystemExit("SDL initialization anchor was not found")
text = text.replace(init_anchor, init_replacement, 1)

window_pattern = re.compile(
    r'''  if \(!SDL_CreateWindowAndRenderer\("M8C", texture_width \* 2, texture_height \* 2,\n'''
    r'''\s+SDL_WINDOW_RESIZABLE \| SDL_WINDOW_HIGH_PIXEL_DENSITY \|\n'''
    r'''\s+SDL_WINDOW_OPENGL \| conf->init_fullscreen,\n'''
    r'''\s+&win, &rend\)\) \{'''
)

text, count = window_pattern.subn(
    '  if (!SDL_CreateWindowAndRenderer("M8C", output_width, output_height, 0, &win, &rend)) {',
    text,
    count=1,
)
if count != 1:
    raise SystemExit("window/renderer creation block was not found")

text = text.replace(
    '  SDL_SetRenderVSync(rend, 1);\n',
    '  SDL_SetRenderVSync(rend, 0);\n',
    1,
)

present_anchor = '''  if (!SDL_RenderPresent(rend)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_RENDER, "Couldn't present renderer: %s", SDL_GetError());
  }
'''

present_replacement = '''  if (!fb_bridge_present(rend)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_RENDER, "Couldn't copy rendered frame to framebuffer.");
  }

''' + present_anchor

if present_anchor not in text:
    raise SystemExit("render-present anchor was not found")
text = text.replace(present_anchor, present_replacement, 1)

required = [
    '#include "fb_bridge.h"',
    'fb_bridge_init("/dev/fb0")',
    'SDL_SetHint(SDL_HINT_RENDER_DRIVER, "software")',
    'SDL_CreateWindowAndRenderer("M8C", output_width, output_height, 0',
    'fb_bridge_present(rend)',
    'fb_bridge_close()',
]
for marker in required:
    if marker not in text:
        raise SystemExit(f"patch validation failed: missing {marker!r}")

if text == original:
    raise SystemExit("patch made no changes")

path.write_text(text, encoding="utf-8")
