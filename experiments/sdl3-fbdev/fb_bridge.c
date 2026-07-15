#include "fb_bridge.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
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
} fb_bridge_state;

static fb_bridge_state state = {
    .fd = -1,
    .memory = NULL,
    .memory_size = 0,
    .initialized = 0,
    .present_failures = 0,
};

static uint32_t scale_channel(const uint8_t value, const struct fb_bitfield field) {
  if (field.length == 0) {
    return 0;
  }

  const uint64_t maximum = (field.length >= 32) ? UINT32_MAX : ((1ULL << field.length) - 1ULL);
  const uint64_t scaled = ((uint64_t)value * maximum + 127ULL) / 255ULL;
  return (uint32_t)(scaled << field.offset);
}

static uint32_t pack_pixel(const uint8_t red, const uint8_t green, const uint8_t blue,
                           const uint8_t alpha) {
  return scale_channel(red, state.variable.red) | scale_channel(green, state.variable.green) |
         scale_channel(blue, state.variable.blue) | scale_channel(alpha, state.variable.transp);
}

static void write_pixel(uint8_t *destination, const uint32_t pixel, const int bytes_per_pixel) {
  switch (bytes_per_pixel) {
  case 2: {
    const uint16_t value = (uint16_t)pixel;
    memcpy(destination, &value, sizeof(value));
    break;
  }
  case 3:
#if SDL_BYTEORDER == SDL_LIL_ENDIAN
    destination[0] = (uint8_t)(pixel & 0xFFU);
    destination[1] = (uint8_t)((pixel >> 8U) & 0xFFU);
    destination[2] = (uint8_t)((pixel >> 16U) & 0xFFU);
#else
    destination[0] = (uint8_t)((pixel >> 16U) & 0xFFU);
    destination[1] = (uint8_t)((pixel >> 8U) & 0xFFU);
    destination[2] = (uint8_t)(pixel & 0xFFU);
#endif
    break;
  case 4:
    memcpy(destination, &pixel, sizeof(pixel));
    break;
  default:
    break;
  }
}

static void log_present_error(const char *message) {
  if (state.present_failures < 5) {
    SDL_LogError(SDL_LOG_CATEGORY_RENDER, "fbdev bridge: %s", message);
  }
  state.present_failures++;
}

int fb_bridge_init(const char *device_path) {
  if (state.initialized) {
    return 1;
  }

  state.fd = open(device_path, O_RDWR | O_CLOEXEC);
  if (state.fd < 0) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev bridge: cannot open %s: %s", device_path,
                    strerror(errno));
    return 0;
  }

  if (ioctl(state.fd, FBIOGET_FSCREENINFO, &state.fixed) < 0) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev bridge: FBIOGET_FSCREENINFO failed: %s",
                    strerror(errno));
    fb_bridge_close();
    return 0;
  }

  if (ioctl(state.fd, FBIOGET_VSCREENINFO, &state.variable) < 0) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev bridge: FBIOGET_VSCREENINFO failed: %s",
                    strerror(errno));
    fb_bridge_close();
    return 0;
  }

  if (state.variable.bits_per_pixel != 16 && state.variable.bits_per_pixel != 24 &&
      state.variable.bits_per_pixel != 32) {
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev bridge: unsupported framebuffer depth: %u",
                    state.variable.bits_per_pixel);
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
    SDL_LogCritical(SDL_LOG_CATEGORY_VIDEO, "fbdev bridge: mmap failed: %s", strerror(errno));
    fb_bridge_close();
    return 0;
  }

  state.initialized = 1;

  SDL_LogInfo(SDL_LOG_CATEGORY_VIDEO,
              "fbdev bridge: %s %ux%u virtual=%ux%u offset=%u,%u bpp=%u stride=%u memory=%zu",
              device_path, state.variable.xres, state.variable.yres, state.variable.xres_virtual,
              state.variable.yres_virtual, state.variable.xoffset, state.variable.yoffset,
              state.variable.bits_per_pixel, state.fixed.line_length, state.memory_size);
  SDL_LogInfo(SDL_LOG_CATEGORY_VIDEO,
              "fbdev bridge: channels R%u@%u G%u@%u B%u@%u A%u@%u visual=%u type=%u",
              state.variable.red.length, state.variable.red.offset, state.variable.green.length,
              state.variable.green.offset, state.variable.blue.length, state.variable.blue.offset,
              state.variable.transp.length, state.variable.transp.offset, state.fixed.visual,
              state.fixed.type);

  return 1;
}

int fb_bridge_width(void) { return state.initialized ? (int)state.variable.xres : 0; }

int fb_bridge_height(void) { return state.initialized ? (int)state.variable.yres : 0; }

bool fb_bridge_present(SDL_Renderer *renderer) {
  if (!state.initialized || renderer == NULL) {
    log_present_error("present requested before initialization");
    return false;
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
  const int bytes_per_pixel = (int)(state.variable.bits_per_pixel / 8U);

  int scaled_width = destination_width;
  int scaled_height = (surface->h * destination_width) / surface->w;
  if (scaled_height > destination_height) {
    scaled_height = destination_height;
    scaled_width = (surface->w * destination_height) / surface->h;
  }

  const int destination_x = (destination_width - scaled_width) / 2;
  const int destination_y = (destination_height - scaled_height) / 2;

  const size_t visible_row_bytes = (size_t)destination_width * (size_t)bytes_per_pixel;
  for (int y = 0; y < destination_height; y++) {
    const size_t framebuffer_y = (size_t)(y + (int)state.variable.yoffset);
    const size_t framebuffer_x = (size_t)state.variable.xoffset * (size_t)bytes_per_pixel;
    uint8_t *row = state.memory + framebuffer_y * (size_t)state.fixed.line_length + framebuffer_x;
    memset(row, 0, visible_row_bytes);
  }

  const int direct_argb =
      surface->w == destination_width && surface->h == destination_height && bytes_per_pixel == 4 &&
      state.variable.red.offset == 16 && state.variable.red.length == 8 &&
      state.variable.green.offset == 8 && state.variable.green.length == 8 &&
      state.variable.blue.offset == 0 && state.variable.blue.length == 8 &&
      (state.variable.transp.length == 0 ||
       (state.variable.transp.offset == 24 && state.variable.transp.length == 8));

  if (direct_argb) {
    for (int y = 0; y < destination_height; y++) {
      const uint8_t *source_row = (const uint8_t *)surface->pixels + (size_t)y * surface->pitch;
      const size_t framebuffer_y = (size_t)(y + (int)state.variable.yoffset);
      const size_t framebuffer_x = (size_t)state.variable.xoffset * 4U;
      uint8_t *destination_row =
          state.memory + framebuffer_y * (size_t)state.fixed.line_length + framebuffer_x;
      memcpy(destination_row, source_row, (size_t)destination_width * 4U);
    }
  } else {
    for (int destination_row_index = 0; destination_row_index < scaled_height;
         destination_row_index++) {
      const int source_y = (destination_row_index * surface->h) / scaled_height;
      const uint32_t *source_row =
          (const uint32_t *)((const uint8_t *)surface->pixels + (size_t)source_y * surface->pitch);

      const int framebuffer_y_index = destination_y + destination_row_index;
      const size_t framebuffer_y =
          (size_t)(framebuffer_y_index + (int)state.variable.yoffset);
      const size_t framebuffer_x =
          (size_t)(destination_x + (int)state.variable.xoffset) * (size_t)bytes_per_pixel;
      uint8_t *destination_row =
          state.memory + framebuffer_y * (size_t)state.fixed.line_length + framebuffer_x;

      for (int destination_column = 0; destination_column < scaled_width;
           destination_column++) {
        const int source_x = (destination_column * surface->w) / scaled_width;
        const uint32_t argb = source_row[source_x];
        const uint8_t alpha = (uint8_t)((argb >> 24U) & 0xFFU);
        const uint8_t red = (uint8_t)((argb >> 16U) & 0xFFU);
        const uint8_t green = (uint8_t)((argb >> 8U) & 0xFFU);
        const uint8_t blue = (uint8_t)(argb & 0xFFU);
        const uint32_t framebuffer_pixel = pack_pixel(red, green, blue, alpha);
        write_pixel(destination_row + (size_t)destination_column * (size_t)bytes_per_pixel,
                    framebuffer_pixel, bytes_per_pixel);
      }
    }
  }

  SDL_DestroySurface(surface);
  state.present_failures = 0;
  return true;
}

void fb_bridge_close(void) {
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
