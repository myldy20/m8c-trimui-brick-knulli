#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-r3.py PATH_TO_M8C_SOURCE")

root = pathlib.Path(sys.argv[1])


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"{description}: anchor not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


render = root / "src" / "render.c"

replace_once(
    render,
    '''  if (!SDL_CreateWindowAndRenderer("M8C", output_width, output_height, 0, &win, &rend)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_APPLICATION, "Couldn't create window and renderer: %s",
                    SDL_GetError());
    return false;
  }
''',
    '''  win = SDL_CreateWindow("M8C", output_width, output_height, 0);
  if (win == NULL) {
    SDL_LogCritical(SDL_LOG_CATEGORY_APPLICATION, "Couldn't create offscreen event window: %s",
                    SDL_GetError());
    return false;
  }

  rend = fb_bridge_create_renderer();
  if (rend == NULL) {
    SDL_LogCritical(SDL_LOG_CATEGORY_APPLICATION, "Couldn't create direct fbdev renderer: %s",
                    SDL_GetError());
    return false;
  }
''',
    "replace offscreen renderer with direct framebuffer renderer",
)

replace_once(
    render,
    '''  if (!fb_bridge_present(rend)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_RENDER, "Couldn't copy rendered frame to framebuffer.");
  }

''',
    '',
    "remove full-frame readback copy",
)

replace_once(
    render,
    '''void renderer_close(void) {
  SDL_LogDebug(SDL_LOG_CATEGORY_RENDER, "Closing renderer");
  fb_bridge_close();
''',
    '''void renderer_close(void) {
  SDL_LogDebug(SDL_LOG_CATEGORY_RENDER, "Closing renderer");
''',
    "delay framebuffer unmap until renderer is destroyed",
)

replace_once(
    render,
    '''  SDL_DestroyRenderer(rend);
  SDL_DestroyWindow(win);
}
''',
    '''  SDL_DestroyRenderer(rend);
  SDL_DestroyWindow(win);
  fb_bridge_close();
}
''',
    "close framebuffer after renderer",
)

# Make the axis handler able to request app exit. Select and Start are exposed
# as trigger axes by the Brick mapping, so a button-only quit check cannot fire.
input_h = root / "src" / "input.h"
replace_once(
    input_h,
    '''void input_handle_gamepad_axis(const struct app_context *ctx, SDL_GamepadAxis axis, Sint16 value);
''',
    '''void input_handle_gamepad_axis(struct app_context *ctx, SDL_GamepadAxis axis, Sint16 value);
''',
    "make axis context mutable in header",
)

input_c = root / "src" / "input.c"
replace_once(
    input_c,
    '''void input_handle_gamepad_axis(const struct app_context *ctx, const SDL_GamepadAxis axis,
                                const Sint16 value) {
''',
    '''void input_handle_gamepad_axis(struct app_context *ctx, const SDL_GamepadAxis axis,
                                const Sint16 value) {
''',
    "make axis context mutable in implementation",
)

replace_once(
    input_c,
    '''  keycode = gamepad_state.current_buttons;

  input_process_and_send(ctx);
}
''',
    '''  keycode = gamepad_state.current_buttons;

#ifdef BRICK_GAMEPAD_ONLY
  if ((gamepad_state.current_buttons & (key_select | key_start)) ==
      (key_select | key_start)) {
    SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "Brick axis exit combination received");
    ctx->app_state = QUIT;
    return;
  }
#endif

  input_process_and_send(ctx);
}
''',
    "add Select+Start axis exit fallback",
)

# The r2 diagnostic log showed repeated SDL button-down notifications from the
# controller. They are harmless after state deduplication but too noisy for a
# release-like test, so remove the temporary per-event log.
text = input_c.read_text(encoding="utf-8")
text, count = re.subn(
    r'''\n  if \(pressed\) \{\n    SDL_LogInfo\(SDL_LOG_CATEGORY_INPUT, "Brick gamepad button down: %d state=0x%02X", button,\n                gamepad_state.current_buttons\);\n  \}\n''',
    '\n',
    text,
    count=1,
)
if count != 1:
    raise SystemExit("remove temporary button log: anchor not found")
input_c.write_text(text, encoding="utf-8")

print("Applied r3 direct-render and exit patches")
