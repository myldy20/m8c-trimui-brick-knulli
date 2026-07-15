#!/usr/bin/env bash
set -Eeuo pipefail

M8C_VERSION="${M8C_VERSION:-2.2.3}"
SDL_VERSION="${SDL_VERSION:-3.2.20}"
PACKAGE_REVISION="${PACKAGE_REVISION:-4}"
OUT_DIR="${OUT_DIR:-/work/dist-fbdev}"
BUILD_DIR="${BUILD_DIR:-/tmp/m8c-fbdev-fast-r4-build}"
PREFIX="${PREFIX:-/opt/m8c-fbdev-prebuilt}"
PREBUILT_R2_DIR="${PREBUILT_R2_DIR:-/work/prebuilt-r2}"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    build-essential \
    binutils \
    pkg-config \
    python3 \
    libserialport-dev \
    patchelf \
    zip
rm -rf /var/lib/apt/lists/*

rm -rf "$BUILD_DIR" "$OUT_DIR" "$PREFIX"
mkdir -p "$BUILD_DIR" "$OUT_DIR" "$PREFIX/lib/pkgconfig" "$PREFIX/include"

PREBUILT_APP="$(find "$PREBUILT_R2_DIR" -type d -path '*/roms/ports/m8c-223-fb-test' -print -quit)"
test -n "$PREBUILT_APP"
test -f "$PREBUILT_APP/lib/libSDL3.so.0"
test -f "$PREBUILT_APP/cdc-acm.ko"
test -f "$PREBUILT_APP/m8c/config.ini"

cp -L "$PREBUILT_APP/lib/libSDL3.so.0" "$PREFIX/lib/libSDL3.so.0"
ln -s libSDL3.so.0 "$PREFIX/lib/libSDL3.so"

cd "$BUILD_DIR"
curl -fL \
    "https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VERSION}/SDL3-${SDL_VERSION}.tar.gz" \
    -o SDL3.tar.gz
tar -xzf SDL3.tar.gz
cp -R "SDL3-${SDL_VERSION}/include/SDL3" "$PREFIX/include/"

cat > "$PREFIX/lib/pkgconfig/sdl3.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: sdl3
Description: Simple DirectMedia Layer 3 prebuilt for TrimUI Brick experiment
Version: $SDL_VERSION
Libs: -L\${libdir} -lSDL3
Cflags: -I\${includedir}
EOF

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export LD_LIBRARY_PATH="$PREFIX/lib"

git clone --depth 1 --branch "v${M8C_VERSION}" https://github.com/laamaa/m8c.git
cp /work/experiments/sdl3-fbdev/fb_bridge.c m8c/src/fb_bridge.c
cp /work/experiments/sdl3-fbdev/fb_bridge.h m8c/src/fb_bridge.h
python3 /work/experiments/sdl3-fbdev/patch-m8c.py m8c/src/render.c
cp /work/experiments/sdl3-fbdev/audio_sdl_brick.c m8c/src/backends/audio_sdl.c
python3 /work/experiments/sdl3-fbdev/patch-r2.py m8c
cp /work/experiments/sdl3-fbdev/fb_bridge_r4.c m8c/src/fb_bridge.c
python3 /work/experiments/sdl3-fbdev/patch-r4.py m8c

cd m8c
make CFLAGS="-DBRICK_GAMEPAD_ONLY" -j"$(nproc)"
cd "$BUILD_DIR"

PACKAGE_NAME="m8c-223-fb-test-${M8C_VERSION}-r${PACKAGE_REVISION}"
PACKAGE_DIR="$OUT_DIR/$PACKAGE_NAME"
PORTS_DIR="$PACKAGE_DIR/roms/ports"
APP_DIR="$PORTS_DIR/m8c-223-fb-test"
mkdir -p "$APP_DIR/lib" "$APP_DIR/m8c"

cp "$BUILD_DIR/m8c/m8c" "$APP_DIR/m8c-bin"
cp -L "$PREFIX/lib/libSDL3.so.0" "$APP_DIR/lib/libSDL3.so.0"
cp "$PREBUILT_APP/cdc-acm.ko" "$APP_DIR/cdc-acm.ko"
cp "$PREBUILT_APP/m8c/config.ini" "$APP_DIR/m8c/config.ini"
cp "$BUILD_DIR/m8c/gamecontrollerdb.txt" "$APP_DIR/m8c/gamecontrollerdb.txt"
cp "$BUILD_DIR/m8c/LICENSE" "$APP_DIR/LICENSE-m8c"
cp "$BUILD_DIR/SDL3-${SDL_VERSION}/LICENSE.txt" "$APP_DIR/LICENSE-SDL.txt"

PREBUILT_LAUNCHER="$(find "$PREBUILT_R2_DIR" -type f -path '*/roms/ports/m8c-223-fb-test.sh' -print -quit)"
test -n "$PREBUILT_LAUNCHER"
cp "$PREBUILT_LAUNCHER" "$PORTS_DIR/m8c-223-fb-test.sh"

cat > "$APP_DIR/VERSIONS.txt" <<EOF
m8c=${M8C_VERSION}
SDL3=${SDL_VERSION}
package_revision=${PACKAGE_REVISION}
video_driver=offscreen
output_bridge=linux-fbdev
framebuffer=/dev/fb0
framebuffer_mode=native-readback-row-expand
render_resolution=320x240
callback_rate_hz=60
framebuffer_active_offset_refresh=true
framebuffer_clear_before_copy=false
input_mode=gamepad-only
analog_dpad_aliases=false
audio_pump=recording-callback-to-playback
exit_combination=select-plus-y
architecture=aarch64
build_userspace=debian-bullseye
EOF

chmod 755 "$APP_DIR/m8c-bin" "$PORTS_DIR/m8c-223-fb-test.sh"
patchelf --set-rpath '$ORIGIN/lib' "$APP_DIR/m8c-bin"
strip --strip-unneeded "$APP_DIR/m8c-bin"
strip --strip-unneeded "$APP_DIR/lib/libSDL3.so.0"

(
    cd "$APP_DIR"
    sha256sum m8c-bin lib/libSDL3.so.0 cdc-acm.ko m8c/config.ini > SHA256SUMS
)

LD_LIBRARY_PATH="$APP_DIR/lib" ldd "$APP_DIR/m8c-bin"
grep -a -q 'fbdev bridge r4' "$APP_DIR/m8c-bin"
bash -n "$PORTS_DIR/m8c-223-fb-test.sh"

cd "$OUT_DIR"
zip -r "${PACKAGE_NAME}.zip" "$PACKAGE_NAME"
sha256sum "${PACKAGE_NAME}.zip" > "${PACKAGE_NAME}.zip.sha256"
printf '%s\n' "$PACKAGE_NAME" > package-name.txt
