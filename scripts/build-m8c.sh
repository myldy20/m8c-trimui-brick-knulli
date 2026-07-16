#!/usr/bin/env bash

cd "$BUILD_DIR"
git clone --depth 1 --branch "v${M8C_VERSION}" https://github.com/laamaa/m8c.git
cp /work/port/fb_bridge.c m8c/src/fb_bridge.c
cp /work/port/fb_bridge.h m8c/src/fb_bridge.h
cp /work/port/brick_input.c m8c/src/brick_input.c
cp /work/port/brick_input.h m8c/src/brick_input.h
cp /work/port/audio_sdl_brick.c m8c/src/backends/audio_sdl.c
python3 /work/port/patch_render.py m8c
python3 /work/port/patch_events.py m8c

cd m8c
make CFLAGS="-DBRICK_RAW_CONTROLS" -j"$(nproc)"
