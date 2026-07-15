#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-r2.py PATH_TO_M8C_SOURCE")

root = pathlib.Path(sys.argv[1])


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"{description}: anchor not found in {path}")
    updated = text.replace(old, new, 1)
    path.write_text(updated, encoding="utf-8")


# The r1 bridge cleared the visible framebuffer before copying each frame. On a
# single-buffer fbdev display that produces an obvious black flash. Refresh the
# active offset for every frame and overwrite the complete composed frame in one
# pass instead.
fb_bridge = root / "src" / "fb_bridge.c"
replace_once(
    fb_bridge,
    """  const int destination_width = (int)state.variable.xres;
""",
    """  struct fb_var_screeninfo current_variable;
  if (ioctl(state.fd, FBIOGET_VSCREENINFO, &current_variable) == 0) {
    state.variable = current_variable;
  }

  const int destination_width = (int)state.variable.xres;
""",
    "refresh framebuffer offsets",
)
replace_once(
    fb_bridge,
    """  const size_t visible_row_bytes = (size_t)destination_width * (size_t)bytes_per_pixel;
  for (int y = 0; y < destination_height; y++) {
    const size_t framebuffer_y = (size_t)(y + (int)state.variable.yoffset);
    const size_t framebuffer_x = (size_t)state.variable.xoffset * (size_t)bytes_per_pixel;
    uint8_t *row = state.memory + framebuffer_y * (size_t)state.fixed.line_length + framebuffer_x;
    memset(row, 0, visible_row_bytes);
  }

""",
    "",
    "remove visible framebuffer clear",
)

# Knulli exposes both the physical SDL gamepad and evmapy's virtual keyboard.
# Processing both causes one physical press to be delivered more than once.
events = root / "src" / "events.c"
replace_once(
    events,
    """  case SDL_EVENT_KEY_DOWN:
""",
    """  case SDL_EVENT_KEY_DOWN:
#ifdef BRICK_GAMEPAD_ONLY
    break;
#endif
""",
    "disable duplicate keyboard key-down events",
)
replace_once(
    events,
    """  case SDL_EVENT_KEY_UP:
""",
    """  case SDL_EVENT_KEY_UP:
#ifdef BRICK_GAMEPAD_ONLY
    break;
#endif
""",
    "disable duplicate keyboard key-up events",
)

# Keep the configured Select+quit combination, accept both SDL face-button
# conventions, and add Select+Start as a reliable Brick-only emergency exit.
input_c = root / "src" / "input.c"
replace_once(
    input_c,
    """  if (pressed && button == conf->gamepad_quit && gamepad_state.current_buttons == key_select) {
    ctx->app_state = QUIT;
    return;
  }
""",
    """  if (pressed) {
    SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "Brick gamepad button down: %d state=0x%02X", button,
                gamepad_state.current_buttons);
  }

  const bool quit_face_button =
      button == conf->gamepad_quit || button == SDL_GAMEPAD_BUTTON_WEST ||
      button == SDL_GAMEPAD_BUTTON_NORTH;
  const bool quit_start_button = button == conf->gamepad_start;
  if (pressed && (gamepad_state.current_buttons & key_select) &&
      (quit_face_button || quit_start_button)) {
    SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "Brick exit combination received");
    ctx->app_state = QUIT;
    return;
  }
""",
    "broaden Brick exit combination",
)

print("Applied r2 framebuffer and input patches")
