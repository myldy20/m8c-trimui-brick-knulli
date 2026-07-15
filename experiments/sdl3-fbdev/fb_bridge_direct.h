#ifndef M8C_FB_BRIDGE_H
#define M8C_FB_BRIDGE_H

#include <SDL3/SDL.h>

int fb_bridge_init(const char *device_path);
int fb_bridge_width(void);
int fb_bridge_height(void);
SDL_Renderer *fb_bridge_create_renderer(void);
bool fb_bridge_present(SDL_Renderer *renderer);
void fb_bridge_close(void);

#endif
