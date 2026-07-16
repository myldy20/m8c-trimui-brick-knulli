#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch_m8c.py PATH_TO_M8C_SOURCE")

root = pathlib.Path(sys.argv[1])


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"{description}: anchor not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


render = root / "src" / "render.c"
replace_once(
    render,
    '#include "render.h"\n',
    '#include "render.h"\n#include "fb_bridge.h"\n',
    "include fbdev bridge",
)
replace_once(
    render,
    'static SDL_Renderer *rend;\n',
    'static SDL_Renderer *rend;\nstatic SDL_Surface *brick_output_surface = NULL;\n',
    "declare completed output surface",
)
replace_once(
    render,
    '''void renderer_close(void) {
  SDL_LogDebug(SDL_LOG_CATEGORY_RENDER, "Closing renderer");
  inline_font_close();
  if (main_texture != NULL) {
    SDL_DestroyTexture(main_texture);
  }
  if (hd_texture != NULL) {
    SDL_DestroyTexture(hd_texture);
  }
  log_overlay_destroy();
  SDL_DestroyRenderer(rend);
  SDL_DestroyWindow(win);
}
''',
    '''void renderer_close(void) {
  SDL_LogDebug(SDL_LOG_CATEGORY_RENDER, "Closing renderer");
  inline_font_close();
  if (main_texture != NULL) {
    SDL_DestroyTexture(main_texture);
  }
  if (hd_texture != NULL) {
    SDL_DestroyTexture(hd_texture);
  }
  log_overlay_destroy();
  SDL_DestroyRenderer(rend);
  rend = NULL;
  if (brick_output_surface != NULL) {
    SDL_DestroySurface(brick_output_surface);
    brick_output_surface = NULL;
  }
  fb_bridge_close();
}
''',
    "replace renderer cleanup",
)
replace_once(
    render,
    '''  if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) == false) {
    SDL_LogCritical(SDL_LOG_CATEGORY_ERROR, "SDL_Init: %s", SDL_GetError());
    return 0;
  }

''',
    '''  if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) == false) {
    SDL_LogCritical(SDL_LOG_CATEGORY_ERROR, "SDL_Init: %s", SDL_GetError());
    return 0;
  }

  if (!fb_bridge_init("/dev/fb0")) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "Failed to initialize fbdev output bridge.");
    return 0;
  }

  SDL_SetHint(SDL_HINT_RENDER_DRIVER, "software");
  conf->integer_scaling = 1;

''',
    "initialize fbdev output",
)
replace_once(
    render,
    '''  if (!SDL_CreateWindowAndRenderer("M8C", texture_width * 2, texture_height * 2,
                                   SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY |
                                       SDL_WINDOW_OPENGL | conf->init_fullscreen,
                                   &win, &rend)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_APPLICATION, "Couldn't create window and renderer: %s",
                    SDL_GetError());
    return false;
  }
''',
    '''  brick_output_surface =
      SDL_CreateSurface(texture_width, texture_height, SDL_PIXELFORMAT_ARGB8888);
  if (brick_output_surface == NULL) {
    SDL_LogCritical(SDL_LOG_CATEGORY_APPLICATION, "Couldn't create Brick output surface: %s",
                    SDL_GetError());
    return false;
  }

  rend = SDL_CreateSoftwareRenderer(brick_output_surface);
  if (rend == NULL) {
    SDL_LogCritical(SDL_LOG_CATEGORY_APPLICATION, "Couldn't create Brick software renderer: %s",
                    SDL_GetError());
    SDL_DestroySurface(brick_output_surface);
    brick_output_surface = NULL;
    return false;
  }
  win = NULL;
  SDL_LogInfo(SDL_LOG_CATEGORY_VIDEO,
              "Brick renderer: completed 320x240 ARGB8888 memory surface, no render readback");
''',
    "create completed memory-surface renderer",
)
replace_once(
    render,
    '  SDL_SetRenderVSync(rend, 1);\n',
    '  SDL_SetRenderVSync(rend, 0);\n',
    "disable unavailable vsync",
)
replace_once(
    render,
    '''  if (!SDL_RenderPresent(rend)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_RENDER, "Couldn't present renderer: %s", SDL_GetError());
  }
''',
    '''  if (!SDL_RenderPresent(rend)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_RENDER, "Couldn't finalize software renderer: %s",
                    SDL_GetError());
  }

  if (!fb_bridge_present(brick_output_surface)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_RENDER, "Couldn't copy completed surface to framebuffer.");
  }
''',
    "present completed surface to fbdev",
)


for marker in ["fb_bridge_present(brick_output_surface)", "SDL_CreateSoftwareRenderer"]:
    if marker not in render.read_text(encoding="utf-8"):
        raise SystemExit(f"validation failed: {marker!r} missing from {render}")

print("Applied TrimUI Brick SDL3/fbdev render patches")
