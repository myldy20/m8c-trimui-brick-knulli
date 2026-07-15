#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-r8-controls-and-rate.py PATH_TO_M8C_SOURCE")

root = pathlib.Path(sys.argv[1])


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"{description}: anchor not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


events = root / "src" / "events.c"

replace_once(
    events,
    '''  static bool brick_select_down = false;
  static bool brick_l2_down = false;
  static Uint8 brick_hat_state = SDL_HAT_CENTERED;
''',
    '''  static bool brick_select_down = false;
  static Uint8 brick_hat_state = SDL_HAT_CENTERED;
''',
    "remove L2 exit state",
)

replace_once(
    events,
    '''    case 0: // B -> Shift
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_select, pressed);
      break;
''',
    '''    case 0: // B -> Shift, or Select+B -> exit
      if (pressed && brick_select_down) {
        SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "Brick Select+B exit combination received");
        ctx->app_state = QUIT;
        break;
      }
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_select, pressed);
      break;
''',
    "change exit to Select plus B",
)

replace_once(
    events,
    '''    case 8: // Select -> Shift
      brick_select_down = pressed;
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_select, pressed);
      break;
    case 9: // Start -> Play
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_start, pressed);
      break;
    case 6: // L2: reserved for Select+L2 exit
      brick_l2_down = pressed;
      break;
''',
    '''    case 8: // Select: modifier for exit only
      brick_select_down = pressed;
      break;
    case 9: // Start: intentionally unused
    case 6: // L2: intentionally unused
      break;
''',
    "remove Select and Start M8 actions",
)

replace_once(
    events,
    '''
    if (brick_select_down && brick_l2_down) {
      SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "Brick Select+L2 exit combination received");
      ctx->app_state = QUIT;
    }
    break;
''',
    '''
    break;
''',
    "remove old Select plus L2 exit",
)

main_c = root / "src" / "main.c"
replace_once(
    main_c,
    '''  // Brick fbdev bridge: process display and input at roughly 60 Hz.
  SDL_SetHint(SDL_HINT_MAIN_CALLBACK_RATE, "60");
''',
    '''  // Keep input and M8 packet processing at the upstream 120 Hz rate.
  // The r4 bridge now works from a 320x240 frame, so this is light enough for
  // the Brick and removes the extra half-frame of input latency introduced by r4.
  SDL_SetHint(SDL_HINT_MAIN_CALLBACK_RATE, "120");
''',
    "restore 120 Hz callback",
)

print("Applied r8 controls and 120 Hz callback")
