#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-r9-surface-and-audio.py PATH_TO_M8C_SOURCE")

root = pathlib.Path(sys.argv[1])


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"{description}: anchor not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


render = root / "src" / "render.c"

replace_once(
    render,
    "static SDL_Renderer *rend;\n",
    "static SDL_Renderer *rend;\nstatic SDL_Surface *brick_output_surface = NULL;\n",
    "declare Brick output surface",
)

replace_once(
    render,
    '''  SDL_DestroyRenderer(rend);
  SDL_DestroyWindow(win);
''',
    '''  SDL_DestroyRenderer(rend);
  rend = NULL;
  if (brick_output_surface != NULL) {
    SDL_DestroySurface(brick_output_surface);
    brick_output_surface = NULL;
  }
  SDL_DestroyWindow(win);
''',
    "destroy Brick output surface",
)

replace_once(
    render,
    '''  if (!SDL_CreateWindowAndRenderer("M8C", texture_width, texture_height, 0, &win, &rend)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_APPLICATION, "Couldn't create window and renderer: %s",
                    SDL_GetError());
    return false;
  }
''',
    '''  brick_output_surface =
      SDL_CreateSurface(texture_width, texture_height, SDL_PIXELFORMAT_ARGB8888);
  if (brick_output_surface == NULL) {
    SDL_LogCritical(SDL_LOG_CATEGORY_APPLICATION, "Couldn't create Brick output surface: %s",
                    SDL_GetError());
    return false;
  }

  rend = SDL_CreateSoftwareRenderer(brick_output_surface);
  if (rend == NULL) {
    SDL_LogCritical(SDL_LOG_CATEGORY_APPLICATION, "Couldn't create Brick software renderer: %s",
                    SDL_GetError());
    SDL_DestroySurface(brick_output_surface);
    brick_output_surface = NULL;
    return false;
  }
  win = NULL;
  SDL_LogInfo(SDL_LOG_CATEGORY_VIDEO,
              "Brick renderer: completed 320x240 ARGB8888 memory surface, no render readback");
''',
    "replace offscreen window with memory surface renderer",
)

replace_once(
    render,
    '''  if (!fb_bridge_present(rend)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_RENDER, "Couldn't copy rendered frame to framebuffer.");
  }

  if (!SDL_RenderPresent(rend)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_RENDER, "Couldn't present renderer: %s", SDL_GetError());
  }
''',
    '''  if (!SDL_RenderPresent(rend)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_RENDER, "Couldn't finalize software renderer: %s",
                    SDL_GetError());
  }

  if (!fb_bridge_present(brick_output_surface)) {
    SDL_LogCritical(SDL_LOG_CATEGORY_RENDER, "Couldn't copy completed surface to framebuffer.");
  }
''',
    "present completed surface after renderer flush",
)

# The first launch after boot can enumerate and open both ALSA devices before
# USB capture actually starts producing samples. Kick both streams a few times
# when the pump sees no data during its startup window.
audio = root / "src" / "backends" / "audio_sdl.c"
replace_once(
    audio,
    '''  unsigned int read_errors = 0;
  unsigned int write_errors = 0;

  SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO, "Brick audio pump thread started");
''',
    '''  unsigned int read_errors = 0;
  unsigned int write_errors = 0;
  unsigned int startup_kicks = 0;
  bool received_audio = false;
  Uint64 silent_since = SDL_GetTicks();

  SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO, "Brick audio pump thread started");
''',
    "add audio startup watchdog state",
)

replace_once(
    audio,
    '''    if (available == 0) {
      SDL_Delay(1);
      continue;
    }
''',
    '''    if (available == 0) {
      const Uint64 now = SDL_GetTicks();
      if (!received_audio && startup_kicks < 3 && now - silent_since >= 1500) {
        startup_kicks++;
        SDL_LogWarn(SDL_LOG_CATEGORY_AUDIO,
                    "Brick audio startup is silent; restarting streams (%u/3)", startup_kicks);
        SDL_PauseAudioStreamDevice(audio_stream_in);
        SDL_PauseAudioStreamDevice(audio_stream_out);
        SDL_ClearAudioStream(audio_stream_in);
        SDL_ClearAudioStream(audio_stream_out);
        SDL_Delay(20);
        SDL_ResumeAudioStreamDevice(audio_stream_out);
        SDL_ResumeAudioStreamDevice(audio_stream_in);
        silent_since = SDL_GetTicks();
      }
      SDL_Delay(1);
      continue;
    }
''',
    "restart initially silent audio streams",
)

replace_once(
    audio,
    '''      if (received == 0) {
        break;
      }

      if (!SDL_PutAudioStreamData(audio_stream_out, temporary, received)) {
''',
    '''      if (received == 0) {
        break;
      }

      if (!received_audio) {
        received_audio = true;
        SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO,
                    "Brick audio capture active after %u startup restart(s)", startup_kicks);
      }

      if (!SDL_PutAudioStreamData(audio_stream_out, temporary, received)) {
''',
    "log first captured audio data",
)

print("Applied r9 completed-surface renderer and audio startup watchdog")
