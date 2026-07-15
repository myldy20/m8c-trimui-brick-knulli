#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-r7-raw-controls.py PATH_TO_M8C_SOURCE")

root = pathlib.Path(sys.argv[1])


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"{description}: anchor not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


events = root / "src" / "events.c"

replace_once(
    events,
    '''SDL_AppResult SDL_AppEvent(void *appstate, SDL_Event *event) {
  struct app_context *ctx = appstate;
  SDL_AppResult ret_val = SDL_APP_CONTINUE;
''',
    '''SDL_AppResult SDL_AppEvent(void *appstate, SDL_Event *event) {
  struct app_context *ctx = appstate;
  SDL_AppResult ret_val = SDL_APP_CONTINUE;
#ifdef BRICK_RAW_CONTROLS
  static bool brick_select_down = false;
  static bool brick_l2_down = false;
  static Uint8 brick_hat_state = SDL_HAT_CENTERED;
#endif
''',
    "add Brick raw input state",
)

# Stop trusting the broken SDL gamepad mapping. All actual controls are handled
# below from the raw joystick button/hat events captured on /dev/input/event3.
replace_once(
    events,
    '''  case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
    if (settings_is_open()) {
      settings_handle_event(ctx, event);
      return ret_val;
    }

    // Allow toggling the settings view using a gamepad only when the device is disconnected to
    // avoid accidentally opening the screen while using the device
    if (event->gbutton.button == SDL_GAMEPAD_BUTTON_BACK) {
      if (ctx->app_state == WAIT_FOR_DEVICE && !settings_is_open()) {
        settings_toggle_open();
      }
    }

    input_handle_gamepad_button(ctx, event->gbutton.button, true);
    break;

  case SDL_EVENT_GAMEPAD_BUTTON_UP:
    if (settings_is_open()) {
      settings_handle_event(ctx, event);
      return ret_val;
    }
    input_handle_gamepad_button(ctx, event->gbutton.button, false);
    break;

  case SDL_EVENT_GAMEPAD_AXIS_MOTION:
    if (settings_is_open()) {
      settings_handle_event(ctx, event);
      return ret_val;
    }
    input_handle_gamepad_axis(ctx, event->gaxis.axis, event->gaxis.value);
    break;
''',
    '''  case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
  case SDL_EVENT_GAMEPAD_BUTTON_UP:
  case SDL_EVENT_GAMEPAD_AXIS_MOTION:
#ifdef BRICK_RAW_CONTROLS
    // Broken vendor mapping: volume and shoulder buttons are mislabeled as
    // Start/Option/Quit. Ignore semantic gamepad events on Brick.
    break;
#else
    if (settings_is_open()) {
      settings_handle_event(ctx, event);
      return ret_val;
    }
    if (event->type == SDL_EVENT_GAMEPAD_BUTTON_DOWN) {
      input_handle_gamepad_button(ctx, event->gbutton.button, true);
    } else if (event->type == SDL_EVENT_GAMEPAD_BUTTON_UP) {
      input_handle_gamepad_button(ctx, event->gbutton.button, false);
    } else {
      input_handle_gamepad_axis(ctx, event->gaxis.axis, event->gaxis.value);
    }
    break;
#endif

#ifdef BRICK_RAW_CONTROLS
  case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
  case SDL_EVENT_JOYSTICK_BUTTON_UP: {
    const bool pressed = event->type == SDL_EVENT_JOYSTICK_BUTTON_DOWN;
    const Uint8 raw = event->jbutton.button;

    // Verified TrimUI Brick raw button numbers:
    // A=1 B=0 X=2 Y=3 L1=4 R1=5 L2=6 R2=7 Select=8 Start=9.
    // Requested layout: Y=Option, X=Edit, B=Shift, A=Play.
    switch (raw) {
    case 1: // A -> Play
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_start, pressed);
      break;
    case 0: // B -> Shift
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_select, pressed);
      break;
    case 2: // X -> Edit
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_edit, pressed);
      break;
    case 3: // Y -> Option
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_opt, pressed);
      break;
    case 8: // Select -> Shift
      brick_select_down = pressed;
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_select, pressed);
      break;
    case 9: // Start -> Play
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_start, pressed);
      break;
    case 6: // L2: reserved for Select+L2 exit
      brick_l2_down = pressed;
      break;
    default:
      // Ignore shoulders, R2 and volume buttons.
      break;
    }

    if (brick_select_down && brick_l2_down) {
      SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "Brick Select+L2 exit combination received");
      ctx->app_state = QUIT;
    }
    break;
  }

  case SDL_EVENT_JOYSTICK_HAT_MOTION: {
    const Uint8 next = event->jhat.value;
    const Uint8 changed = brick_hat_state ^ next;

    if (changed & SDL_HAT_UP) {
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_up, (next & SDL_HAT_UP) != 0);
    }
    if (changed & SDL_HAT_RIGHT) {
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_right, (next & SDL_HAT_RIGHT) != 0);
    }
    if (changed & SDL_HAT_DOWN) {
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_down, (next & SDL_HAT_DOWN) != 0);
    }
    if (changed & SDL_HAT_LEFT) {
      input_handle_gamepad_button(ctx, ctx->conf.gamepad_left, (next & SDL_HAT_LEFT) != 0);
    }

    brick_hat_state = next;
    break;
  }
#endif
''',
    "replace semantic gamepad mapping with raw controls",
)

# r5 admitted a handful of keyboard aliases. Raw joystick input now covers all
# face buttons, so suppress the virtual keyboard again to avoid volume/hotkey
# surprises and duplicate controls.
replace_once(
    events,
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
    '''  case SDL_EVENT_KEY_DOWN:
#ifdef BRICK_RAW_CONTROLS
    break;
#elif defined(BRICK_GAMEPAD_ONLY)
    if (event->key.scancode != ctx->conf.key_opt_alt &&
        event->key.scancode != ctx->conf.key_edit_alt &&
        event->key.scancode != ctx->conf.key_select_alt &&
        event->key.scancode != ctx->conf.key_start_alt) {
      break;
    }
#endif
''',
    "suppress virtual keyboard key-down events",
)
replace_once(
    events,
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
    '''  case SDL_EVENT_KEY_UP:
#ifdef BRICK_RAW_CONTROLS
    break;
#elif defined(BRICK_GAMEPAD_ONLY)
    if (event->key.scancode != ctx->conf.key_opt_alt &&
        event->key.scancode != ctx->conf.key_edit_alt &&
        event->key.scancode != ctx->conf.key_select_alt &&
        event->key.scancode != ctx->conf.key_start_alt) {
      break;
    }
#endif
''',
    "suppress virtual keyboard key-up events",
)

print("Applied r7 raw TrimUI Brick control mapping")
