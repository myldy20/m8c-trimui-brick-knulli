#include "brick_input.h"

#include "input.h"

#include <stdlib.h>
#include <string.h>

static bool select_down = false;
static Uint8 hat_state = SDL_HAT_CENTERED;
static int profile = -1; // 0=face, 1=classic

static void initialize_profile(void) {
  if (profile >= 0) {
    return;
  }

  const char *value = getenv("M8C_CONTROL_PROFILE");
  profile = value != NULL && strcmp(value, "classic") == 0 ? 1 : 0;
  SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "Brick control profile: %s",
              profile == 1 ? "classic" : "face");
}

static void send_button(struct app_context *ctx, int mapped_button, bool pressed) {
  input_handle_gamepad_button(ctx, mapped_button, pressed);
}

static void handle_face_button(struct app_context *ctx, Uint8 raw, bool pressed) {
  // Face: A=Play, B=Shift, X=Edit, Y=Option; Select+B exits.
  switch (raw) {
  case 0: // B
    if (pressed && select_down) {
      SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "Brick Select+B exit combination received");
      ctx->app_state = QUIT;
    } else {
      send_button(ctx, ctx->conf.gamepad_select, pressed);
    }
    break;
  case 1: // A
    send_button(ctx, ctx->conf.gamepad_start, pressed);
    break;
  case 2: // X
    send_button(ctx, ctx->conf.gamepad_edit, pressed);
    break;
  case 3: // Y
    send_button(ctx, ctx->conf.gamepad_opt, pressed);
    break;
  default:
    break;
  }
}

static void handle_classic_button(struct app_context *ctx, Uint8 raw, bool pressed) {
  // Classic: A=Option, B=Edit, Select=Shift, Start=Play; Select+Y exits.
  switch (raw) {
  case 0: // B
    send_button(ctx, ctx->conf.gamepad_edit, pressed);
    break;
  case 1: // A
    send_button(ctx, ctx->conf.gamepad_opt, pressed);
    break;
  case 3: // Y
    if (pressed && select_down) {
      SDL_LogInfo(SDL_LOG_CATEGORY_INPUT, "Brick Select+Y exit combination received");
      ctx->app_state = QUIT;
    }
    break;
  case 9: // Start
    send_button(ctx, ctx->conf.gamepad_start, pressed);
    break;
  default:
    break;
  }
}

static void handle_raw_button(struct app_context *ctx, SDL_Event *event) {
  const bool pressed = event->type == SDL_EVENT_JOYSTICK_BUTTON_DOWN;
  const Uint8 raw = event->jbutton.button;

  // Verified raw buttons: B0 A1 X2 Y3 L1-4 R1-5 L2-6 R2-7 Select-8 Start-9.
  if (raw == 8) {
    select_down = pressed;
    if (profile == 1) {
      send_button(ctx, ctx->conf.gamepad_select, pressed);
    }
    return;
  }

  if (profile == 0) {
    handle_face_button(ctx, raw, pressed);
  } else {
    handle_classic_button(ctx, raw, pressed);
  }
}

static void handle_hat(struct app_context *ctx, Uint8 next) {
  const Uint8 changed = hat_state ^ next;

  if (changed & SDL_HAT_UP) {
    send_button(ctx, ctx->conf.gamepad_up, (next & SDL_HAT_UP) != 0);
  }
  if (changed & SDL_HAT_RIGHT) {
    send_button(ctx, ctx->conf.gamepad_right, (next & SDL_HAT_RIGHT) != 0);
  }
  if (changed & SDL_HAT_DOWN) {
    send_button(ctx, ctx->conf.gamepad_down, (next & SDL_HAT_DOWN) != 0);
  }
  if (changed & SDL_HAT_LEFT) {
    send_button(ctx, ctx->conf.gamepad_left, (next & SDL_HAT_LEFT) != 0);
  }

  hat_state = next;
}

bool brick_input_handle(struct app_context *ctx, SDL_Event *event) {
  initialize_profile();

  switch (event->type) {
  case SDL_EVENT_KEY_DOWN:
  case SDL_EVENT_KEY_UP:
    // Knulli emits virtual keyboard aliases; raw joystick events are authoritative.
    return true;

  case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
  case SDL_EVENT_GAMEPAD_BUTTON_UP:
  case SDL_EVENT_GAMEPAD_AXIS_MOTION:
    // The Brick's SDL semantic mapping is wrong; ignore it.
    return true;

  case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
  case SDL_EVENT_JOYSTICK_BUTTON_UP:
    handle_raw_button(ctx, event);
    return true;

  case SDL_EVENT_JOYSTICK_HAT_MOTION:
    handle_hat(ctx, event->jhat.value);
    return true;

  default:
    return false;
  }
}
