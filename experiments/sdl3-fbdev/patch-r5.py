#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-r5.py PATH_TO_M8C_SOURCE")

root = pathlib.Path(sys.argv[1])


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"{description}: anchor not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# On Knulli, d-pad/Select/Start arrive through SDL's physical gamepad, but the
# four face buttons are emitted by evmapy's virtual keyboard. r2 suppressed all
# keyboard events to remove duplicate d-pad moves, which also removed A/B/X/Y.
# Accept only the four letter-key aliases used by the Brick launcher config.
events = root / "src" / "events.c"
replace_once(
    events,
    '''  case SDL_EVENT_KEY_DOWN:
#ifdef BRICK_GAMEPAD_ONLY
    break;
#endif
''',
    '''  case SDL_EVENT_KEY_DOWN:
#ifdef BRICK_GAMEPAD_ONLY
    if (event->key.scancode != ctx->conf.key_opt_alt &&
        event->key.scancode != ctx->conf.key_edit_alt &&
        event->key.scancode != ctx->conf.key_select_alt &&
        event->key.scancode != ctx->conf.key_start_alt) {
      break;
    }
#endif
''',
    "restore face-button key-down aliases",
)
replace_once(
    events,
    '''  case SDL_EVENT_KEY_UP:
#ifdef BRICK_GAMEPAD_ONLY
    break;
#endif
''',
    '''  case SDL_EVENT_KEY_UP:
#ifdef BRICK_GAMEPAD_ONLY
    if (event->key.scancode != ctx->conf.key_opt_alt &&
        event->key.scancode != ctx->conf.key_edit_alt &&
        event->key.scancode != ctx->conf.key_select_alt &&
        event->key.scancode != ctx->conf.key_start_alt) {
      break;
    }
#endif
''',
    "restore face-button key-up aliases",
)

input_c = root / "src" / "input.c"
replace_once(
    input_c,
    '''  if (event->key.repeat > 0) {
    return;
  }

''',
    '''  if (event->key.repeat > 0) {
    return;
  }

#ifdef BRICK_GAMEPAD_ONLY
  // Physical Y is evmapy's Z-key alias. Select itself arrives through the
  // gamepad, so the normal button-only quit check can never see both events.
  if (event->key.scancode == ctx->conf.key_select_alt &&
      (gamepad_state.current_buttons & key_select)) {
    SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "Brick Select+Y exit combination received");
    ctx->app_state = QUIT;
    return;
  }
#endif

''',
    "add hybrid Select plus Y exit",
)

print("Applied r5 Brick face-button and exit patches")
