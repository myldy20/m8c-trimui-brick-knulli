#ifndef M8C_BRICK_INPUT_H
#define M8C_BRICK_INPUT_H

#include "common.h"
#include <SDL3/SDL.h>

bool brick_input_handle(struct app_context *ctx, SDL_Event *event);

#endif
