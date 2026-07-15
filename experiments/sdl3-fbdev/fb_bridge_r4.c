#include "fb_bridge.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
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
  int initialized;
  unsigned int present_failures;

  int *x_map;
  int x_map_source_width;
  int x_map_scaled_width;
  uint32_t *expanded_row;
  int expanded_row_width;

  int layout_initialized;
  int last_source_width;
  int last_source_height;
  int last_scaled_width;
  int last_scaled_height;
  int last_destination_x;
  int last_destination_y;
} fb_bridge_state;

static fb_bridge_state state = {
    .fd = -1,
    .memory = NULL,
    .memory_size = 0,
    .initialized = 0,
    .present_failures = 0,
    .x_map = NULL,
    .x_map_source_width = 0,
    .x_map_scaled_width = 0,
    .expanded_row = NULL,
    .expanded_row_width = 0,
    .layout_initialized = 0,
};

static void log_present_error(const char *message) {
  if (state.present_failures < 5) {
    SDL_LogError(SDL_LOG_CATEGORY_RENDER, "fbdev bridge r4: %s", message);
  }
  state.present_failures++;
}

static int framebuffer_is_argb8888(void) {
  return state.variable.bits_per_pixel == 32 && state.variable.red.offset == 16 &&
         state.variable.red.length == 8 && state.variable.green.offset == 8 &&
         state.variable.green.length == 8 && state.variable.blue.offset == 0 &&
         state.variable.blue.length == 8 &&
         (state.variable.transp.length == 0 ||
          (state.variable.transp.offset == 24 && state.variable.transp.length == 8));
}

static int ensure_x_map(const int source_width, const int scaled_width) {
  if (state.x_map != NULL && state.x_map_source_width == source_width &&
      state.x_map_scaled_width == scaled_width) {
    return 1;
  }

  int *replacement = realloc(state.x_map, (size_t)scaled_width * sizeof(*replacement));
  if (replacement == NULL) {
    log_present_error("cannot allocate horizontal scaling map");
    return 0;
  }

  state.x_map = replacement;
  state.x_map_source_width = source_width;
  state.x_map_scaled_width = scaled_width;

  for (int x = 0; x < scaled_width; x++) {
    state.x_map[x] = (x * source_width) / scaled_width;
  }

  return 1;
}

static int ensure_expanded_row(const int scaled_width) {
  if (state.expanded_row != NULL && state.expanded_row_width >= scaled_width) {
    return 1;
  }

  uint32_t *replacement =
      realloc(state.expanded_row, (size_t)scaled_width * sizeof(*replacement));
  if (replacement == NULL) {
    log_present_error("cannot allocate expanded framebuffer row");
    return 0;
  }

  state.expanded_row = replacement;
  state.expanded_row_width = scaled_width;
  return 1;
}

static void clear_letterbox_once(const int destination_width, const int destination_height,
                                 const int destination_x, const int destination_y,
                                 const int scaled_width, const int scaled_height) {
  const int layout_changed =
      !state.layout_initialized || state.last_scaled_width != scaled_width ||
      state.last_scaled_height != scaled_height || state.last_destination_x != destination_x ||
      state.last_destination_y != destination_y;

  if (!layout_changed) {
    return;
  }

  const size_t visible_row_bytes = (size_t)destination_width * 4U;
  for (int y = 0; y < destination_height; y++) {
    const size_t framebuffer_y = (size_t)(y + (int)state.variable.yoffset);
    const size_t framebuffer_x = (size_t)state.variable.xoffset * 4U;
    uint8_t *row = state.memory + framebuffer_y * (size_t)state.fixed.line_length + framebuffer_x;
    memset(row, 0, visible_row_bytes);
  }

  state.layout_initialized = 1;
  state.last_scaled_width = scaled_width;
  state.last_scaled_height = scaled_height;
  state.last_destination_x = destination_x;
  state.last_destination_y = destination_y;
}

int fb_bridge_init(const char *device_path) {
  if (state.initialized) {
    return 1;
  }

  state.fd = open(device_path, O_RDWR | O_CLOEXEC);
  if (state.fd < 0) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev bridge r4: cannot open %s: %s", device_path,
                    strerror(errno));
    return 0;
  }

  if (ioctl(state.fd, FBIOGET_FSCREENINFO, &state.fixed) < 0) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev bridge r4: FBIOGET_FSCREENINFO failed: %s",
                    strerror(errno));
    fb_bridge_close();
    return 0;
  }

  if (ioctl(state.fd, FBIOGET_VSCREENINFO, &state.variable) < 0) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev bridge r4: FBIOGET_VSCREENINFO failed: %s",
                    strerror(errno));
    fb_bridge_close();
    return 0;
  }

  if (!framebuffer_is_argb8888()) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO,
                    "fbdev bridge r4: expected Brick ARGB8888 framebuffer, got bpp=%u "
                    "R%u@%u G%u@%u B%u@%u A%u@%u",
                    state.variable.bits_per_pixel, state.variable.red.length,
                    state.variable.red.offset, state.variable.green.length,
                    state.variable.green.offset, state.variable.blue.length,
                    state.variable.blue.offset, state.variable.transp.length,
                    state.variable.transp.offset);
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
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev bridge r4: mmap failed: %s", strerror(errno));
    fb_bridge_close();
    return 0;
  }

  state.initialized = 1;

  SDL_LogInfo(SDL_LOG_CATEGORY_VIDEO,
              "fbdev bridge r4: %s %ux%u virtual=%ux%u offset=%u,%u bpp=%u stride=%u "
              "memory=%zu",
              device_path, state.variable.xres, state.variable.yres, state.variable.xres_virtual,
              state.variable.yres_virtual, state.variable.xoffset, state.variable.yoffset,
              state.variable.bits_per_pixel, state.fixed.line_length, state.memory_size);
  SDL_LogInfo(SDL_LOG_CATEGORY_VIDEO,
              "fbdev bridge r4: native-resolution readback with cached nearest-neighbour row "
              "expansion");

  return 1;
}

int fb_bridge_width(void) { return state.initialized ? (int)state.variable.xres : 0; }

int fb_bridge_height(void) { return state.initialized ? (int)state.variable.yres : 0; }

bool fb_bridge_present(SDL_Renderer *renderer) {
  if (!state.initialized || renderer == NULL) {
    log_present_error("present requested before initialization");
    return false;
  }

  struct fb_var_screeninfo current_variable;
  if (ioctl(state.fd, FBIOGET_VSCREENINFO, &current_variable) == 0) {
    state.variable = current_variable;
  }

  SDL_Surface *surface = SDL_RenderReadPixels(renderer, NULL);
  if (surface == NULL) {
    log_present_error(SDL_GetError());
    return false;
  }

  if (surface->format != SDL_PIXELFORMAT_ARGB8888) {
    SDL_Surface *converted = SDL_ConvertSurface(surface, SDL_PIXELFORMAT_ARGB8888);
    SDL_DestroySurface(surface);
    surface = converted;
    if (surface == NULL) {
      log_present_error(SDL_GetError());
      return false;
    }
  }

  const int destination_width = (int)state.variable.xres;
  const int destination_height = (int)state.variable.yres;

  int scaled_width = destination_width;
  int scaled_height = (surface->h * destination_width) / surface->w;
  if (scaled_height > destination_height) {
    scaled_height = destination_height;
    scaled_width = (surface->w * destination_height) / surface->h;
  }

  const int destination_x = (destination_width - scaled_width) / 2;
  const int destination_y = (destination_height - scaled_height) / 2;

  if (!ensure_x_map(surface->w, scaled_width) || !ensure_expanded_row(scaled_width)) {
    SDL_DestroySurface(surface);
    return false;
  }

  clear_letterbox_once(destination_width, destination_height, destination_x, destination_y,
                       scaled_width, scaled_height);

  if (state.last_source_width != surface->w || state.last_source_height != surface->h) {
    state.last_source_width = surface->w;
    state.last_source_height = surface->h;
    SDL_LogInfo(SDL_LOG_CATEGORY_VIDEO,
                "fbdev bridge r4: source=%dx%d scaled=%dx%d destination=%dx%d offset=%d,%d",
                surface->w, surface->h, scaled_width, scaled_height, destination_width,
                destination_height, destination_x, destination_y);
  }

  for (int source_y = 0; source_y < surface->h; source_y++) {
    const uint32_t *source_row =
        (const uint32_t *)((const uint8_t *)surface->pixels + (size_t)source_y * surface->pitch);

    for (int x = 0; x < scaled_width; x++) {
      state.expanded_row[x] = source_row[state.x_map[x]];
    }

    const int first_destination_y = destination_y + (source_y * scaled_height) / surface->h;
    const int after_last_destination_y =
        destination_y + ((source_y + 1) * scaled_height) / surface->h;

    for (int y = first_destination_y; y < after_last_destination_y; y++) {
      const size_t framebuffer_y = (size_t)(y + (int)state.variable.yoffset);
      const size_t framebuffer_x = (size_t)(destination_x + (int)state.variable.xoffset) * 4U;
      const size_t byte_offset =
          framebuffer_y * (size_t)state.fixed.line_length + framebuffer_x;
      const size_t row_bytes = (size_t)scaled_width * 4U;

      if (byte_offset + row_bytes <= state.memory_size) {
        memcpy(state.memory + byte_offset, state.expanded_row, row_bytes);
      }
    }
  }

  SDL_DestroySurface(surface);
  state.present_failures = 0;
  return true;
}

void fb_bridge_close(void) {
  free(state.x_map);
  state.x_map = NULL;
  state.x_map_source_width = 0;
  state.x_map_scaled_width = 0;

  free(state.expanded_row);
  state.expanded_row = NULL;
  state.expanded_row_width = 0;

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
  state.layout_initialized = 0;
}
