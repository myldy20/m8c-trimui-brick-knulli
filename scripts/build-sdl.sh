#!/usr/bin/env bash

cd "$BUILD_DIR"
curl -fL \
    "https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VERSION}/SDL3-${SDL_VERSION}.tar.gz" \
    -o SDL3.tar.gz
tar -xzf SDL3.tar.gz

cmake \
    -S "SDL3-${SDL_VERSION}" \
    -B sdl-build \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DSDL_SHARED=ON \
    -DSDL_STATIC=OFF \
    -DSDL_TEST_LIBRARY=OFF \
    -DSDL_TESTS=OFF \
    -DSDL_EXAMPLES=OFF \
    -DSDL_UNIX_CONSOLE_BUILD=ON \
    -DSDL_DEPS_SHARED=ON \
    -DSDL_DUMMYVIDEO=ON \
    -DSDL_OFFSCREEN=ON \
    -DSDL_X11=OFF \
    -DSDL_WAYLAND=OFF \
    -DSDL_KMSDRM=OFF \
    -DSDL_OPENGL=OFF \
    -DSDL_OPENGLES=OFF \
    -DSDL_VULKAN=OFF \
    -DSDL_RPI=OFF \
    -DSDL_ROCKCHIP=OFF \
    -DSDL_ALSA=ON \
    -DSDL_ALSA_SHARED=ON \
    -DSDL_PIPEWIRE=OFF \
    -DSDL_PULSEAUDIO=OFF \
    -DSDL_JACK=OFF \
    -DSDL_SNDIO=OFF \
    -DSDL_OSS=OFF \
    -DSDL_DBUS=OFF \
    -DSDL_IBUS=OFF \
    -DSDL_LIBURING=OFF \
    -DSDL_HIDAPI_LIBUSB=OFF

cmake --build sdl-build --parallel
cmake --install sdl-build

SDL_PC_FILE="$(find "$PREFIX" -type f -name sdl3.pc -print -quit)"
SDL_LIBRARY="$(find "$PREFIX" -type f -name 'libSDL3.so.0*' -print -quit)"
test -n "$SDL_PC_FILE"
test -n "$SDL_LIBRARY"
export SDL_PC_FILE SDL_LIBRARY
export PKG_CONFIG_PATH="$(dirname "$SDL_PC_FILE")"
export LD_LIBRARY_PATH="$PREFIX/lib"
