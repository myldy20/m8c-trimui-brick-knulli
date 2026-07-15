#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-r6-input-diagnostics.py PATH_TO_M8C_SOURCE")

root = pathlib.Path(sys.argv[1])


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"{description}: anchor not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


events = root / "src" / "events.c"
replace_once(
    events,
    '''  SDL_AppResult ret_val = SDL_APP_CONTINUE;

  switch (event->type) {
''',
    '''  SDL_AppResult ret_val = SDL_APP_CONTINUE;

#ifdef BRICK_INPUT_DIAGNOSTICS
  switch (event->type) {
  case SDL_EVENT_KEY_DOWN:
  case SDL_EVENT_KEY_UP:
    SDL_LogInfo(SDL_LOG_CATEGORY_INPUT,
                "INPUTDIAG keyboard action=%s scancode=%d key=%d repeat=%d mod=0x%X",
                event->type == SDL_EVENT_KEY_DOWN ? "down" : "up", event->key.scancode,
                (int)event->key.key, event->key.repeat, (unsigned int)event->key.mod);
    break;
  case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
  case SDL_EVENT_GAMEPAD_BUTTON_UP:
    SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "INPUTDIAG gamepad-button action=%s which=%u button=%u",
                event->type == SDL_EVENT_GAMEPAD_BUTTON_DOWN ? "down" : "up",
                (unsigned int)event->gbutton.which, (unsigned int)event->gbutton.button);
    break;
  case SDL_EVENT_GAMEPAD_AXIS_MOTION:
    if (event->gaxis.value > 12000 || event->gaxis.value < -12000 || event->gaxis.value == 0) {
      SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "INPUTDIAG gamepad-axis which=%u axis=%u value=%d",
                  (unsigned int)event->gaxis.which, (unsigned int)event->gaxis.axis,
                  (int)event->gaxis.value);
    }
    break;
  case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
  case SDL_EVENT_JOYSTICK_BUTTON_UP:
    SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "INPUTDIAG joystick-button action=%s which=%u button=%u",
                event->type == SDL_EVENT_JOYSTICK_BUTTON_DOWN ? "down" : "up",
                (unsigned int)event->jbutton.which, (unsigned int)event->jbutton.button);
    break;
  case SDL_EVENT_JOYSTICK_AXIS_MOTION:
    if (event->jaxis.value > 12000 || event->jaxis.value < -12000 || event->jaxis.value == 0) {
      SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "INPUTDIAG joystick-axis which=%u axis=%u value=%d",
                  (unsigned int)event->jaxis.which, (unsigned int)event->jaxis.axis,
                  (int)event->jaxis.value);
    }
    break;
  case SDL_EVENT_JOYSTICK_HAT_MOTION:
    SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "INPUTDIAG joystick-hat which=%u hat=%u value=%u",
                (unsigned int)event->jhat.which, (unsigned int)event->jhat.hat,
                (unsigned int)event->jhat.value);
    break;
  default:
    break;
  }
#endif

  switch (event->type) {
''',
    "add raw input diagnostics",
)

gamepads = root / "src" / "gamepads.c"
replace_once(
    gamepads,
    '''    SDL_Log("Controller %d: %s", controller_index + 1,
            SDL_GetGamepadName(game_controllers[controller_index]));
    controller_index++;
''',
    '''    SDL_Log("Controller %d: %s", controller_index + 1,
            SDL_GetGamepadName(game_controllers[controller_index]));
#ifdef BRICK_INPUT_DIAGNOSTICS
    char guid_text[64] = {0};
    const SDL_GUID guid = SDL_GetGamepadGUIDForID(joystick_ids[i]);
    SDL_GUIDToString(guid, guid_text, sizeof(guid_text));
    char *mapping = SDL_GetGamepadMappingForID(joystick_ids[i]);
    SDL_LogInfo(SDL_LOG_CATEGORY_INPUT,
                "INPUTDIAG device id=%u name=%s path=%s guid=%s vendor=0x%04X product=0x%04X",
                (unsigned int)joystick_ids[i], SDL_GetGamepadNameForID(joystick_ids[i]),
                SDL_GetGamepadPathForID(joystick_ids[i]), guid_text,
                SDL_GetGamepadVendorForID(joystick_ids[i]),
                SDL_GetGamepadProductForID(joystick_ids[i]));
    SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "INPUTDIAG mapping=%s",
                mapping != NULL ? mapping : "<none>");
    SDL_free(mapping);
#endif
    controller_index++;
''',
    "log controller GUID and SDL mapping",
)

print("Applied r6 Brick input diagnostics")
