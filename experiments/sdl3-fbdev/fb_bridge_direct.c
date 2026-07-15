#include "fb_bridge.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

typedef struct fb_bridge_state {
  int fd;
  uint8_t *memory;
  size_t memory_size;
  struct fb_fix_screeninfo fixed;
  struct fb_var_screeninfo variable;
  SDL_Surface *surface;
  int initialized;
} fb_bridge_state;

static fb_bridge_state state = {
    .fd = -1,
    .memory = NULL,
    .memory_size = 0,
    .surface = NULL,
    .initialized = 0,
};

int fb_bridge_init(const char *device_path) {
  if (state.initialized) {
    return 1;
  }

  state.fd = open(device_path, O_RDWR | O_CLOEXEC);
  if (state.fd < 0) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev direct: cannot open %s: %s", device_path,
                    strerror(errno));
    return 0;
  }

  if (ioctl(state.fd, FBIOGET_FSCREENINFO, &state.fixed) < 0 ||
      ioctl(state.fd, FBIOGET_VSCREENINFO, &state.variable) < 0) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev direct: cannot query framebuffer: %s",
                    strerror(errno));
    fb_bridge_close();
    return 0;
  }

  if (state.variable.bits_per_pixel != 32 || state.variable.red.offset != 16 ||
      state.variable.red.length != 8 || state.variable.green.offset != 8 ||
      state.variable.green.length != 8 || state.variable.blue.offset != 0 ||
      state.variable.blue.length != 8) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO,
                    "fbdev direct: unsupported pixel layout bpp=%u R%u@%u G%u@%u B%u@%u",
                    state.variable.bits_per_pixel, state.variable.red.length,
                    state.variable.red.offset, state.variable.green.length,
                    state.variable.green.offset, state.variable.blue.length,
                    state.variable.blue.offset);
    fb_bridge_close();
    return 0;
  }

  state.memory_size = state.fixed.smem_len;
  if (state.memory_size == 0) {
    state.memory_size = (size_t)state.fixed.line_length * (size_t)state.variable.yres_virtual;
  }

  state.memory = mmap(NULL, state.memory_size, PROT_READ | PROT_WRITE, MAP_SHARED, state.fd, 0);
  if (state.memory == MAP_FAILED) {
    state.memory = NULL;
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev direct: mmap failed: %s", strerror(errno));
    fb_bridge_close();
    return 0;
  }

  const size_t byte_offset =
      (size_t)state.variable.yoffset * (size_t)state.fixed.line_length +
      (size_t)state.variable.xoffset * 4U;
  if (byte_offset >= state.memory_size) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev direct: active page offset is outside memory");
    fb_bridge_close();
    return 0;
  }

  state.surface =
      SDL_CreateSurfaceFrom((int)state.variable.xres, (int)state.variable.yres,
                            SDL_PIXELFORMAT_ARGB8888, state.memory + byte_offset,
                            (int)state.fixed.line_length);
  if (state.surface == NULL) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev direct: surface creation failed: %s",
                    SDL_GetError());
    fb_bridge_close();
    return 0;
  }

  state.initialized = 1;

  SDL_LogInfo(SDL_LOG_CATEGORY_VIDEO,
              "fbdev direct: %s %ux%u virtual=%ux%u offset=%u,%u bpp=%u stride=%u memory=%zu",
              device_path, state.variable.xres, state.variable.yres,
              state.variable.xres_virtual, state.variable.yres_virtual,
              state.variable.xoffset, state.variable.yoffset,
              state.variable.bits_per_pixel, state.fixed.line_length, state.memory_size);
  SDL_LogInfo(SDL_LOG_CATEGORY_VIDEO,
              "fbdev direct: SDL software renderer will draw into mapped framebuffer memory");

  return 1;
}

int fb_bridge_width(void) { return state.initialized ? (int)state.variable.xres : 0; }

int fb_bridge_height(void) { return state.initialized ? (int)state.variable.yres : 0; }

SDL_Renderer *fb_bridge_create_renderer(void) {
  if (!state.initialized || state.surface == NULL) {
    SDL_LogCritical(SDL_LOG_CATEGORY_RENDER,
                    "fbdev direct: renderer requested before framebuffer initialization");
    return NULL;
  }

  SDL_Renderer *renderer = SDL_CreateSoftwareRenderer(state.surface);
  if (renderer == NULL) {
    SDL_LogCritical(SDL_LOG_CATEGORY_RENDER, "fbdev direct: software renderer failed: %s",
                    SDL_GetError());
    return NULL;
  }

  SDL_LogInfo(SDL_LOG_CATEGORY_RENDER, "fbdev direct: renderer=%s",
              SDL_GetRendererName(renderer));
  return renderer;
}

bool fb_bridge_present(SDL_Renderer *renderer) {
  (void)renderer;
  return true;
}

void fb_bridge_close(void) {
  if (state.surface != NULL) {
    SDL_DestroySurface(state.surface);
    state.surface = NULL;
  }

  if (state.memory != NULL) {
    munmap(state.memory, state.memory_size);
    state.memory = NULL;
  }

  if (state.fd >= 0) {
    close(state.fd);
    state.fd = -1;
  }

  state.memory_size = 0;
  state.initialized = 0;
}
