#!/usr/bin/env bash
set -Eeuo pipefail

M8C_VERSION="${M8C_VERSION:-2.2.3}"
SDL_VERSION="${SDL_VERSION:-3.2.20}"
PACKAGE_REVISION="${PACKAGE_REVISION:-1}"
ORIGINAL_PORT_TAG="${ORIGINAL_PORT_TAG:-v0.1}"
OUT_DIR="${OUT_DIR:-/work/dist-fbdev}"
BUILD_DIR="${BUILD_DIR:-/tmp/m8c-fbdev-build}"
PREFIX="${PREFIX:-/opt/m8c-fbdev}"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    build-essential \
    binutils \
    pkg-config \
    python3-pip \
    libserialport-dev \
    libasound2-dev \
    libudev-dev \
    patchelf \
    unzip \
    zip
rm -rf /var/lib/apt/lists/*

python3 -m pip install --no-cache-dir cmake==3.31.6 ninja==1.11.1.1

rm -rf "$BUILD_DIR" "$OUT_DIR" "$PREFIX"
mkdir -p "$BUILD_DIR" "$OUT_DIR"
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
test -n "$SDL_PC_FILE"
export PKG_CONFIG_PATH="$(dirname "$SDL_PC_FILE")${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

SDL_LIBRARY="$(find "$PREFIX" -type f -name 'libSDL3.so.0*' -print -quit)"
test -n "$SDL_LIBRARY"

git clone --depth 1 --branch "v${M8C_VERSION}" https://github.com/laamaa/m8c.git
cp /work/experiments/sdl3-fbdev/fb_bridge.c m8c/src/fb_bridge.c
cp /work/experiments/sdl3-fbdev/fb_bridge.h m8c/src/fb_bridge.h
python3 /work/experiments/sdl3-fbdev/patch-m8c.py m8c/src/render.c

cd m8c
make -j"$(nproc)"
cd "$BUILD_DIR"

curl -fsSL \
    "https://api.github.com/repos/f32-0/m8c-brick-knulli/releases/tags/${ORIGINAL_PORT_TAG}" \
    -o original-port-release.json

ORIGINAL_PORT_URL="$(python3 - original-port-release.json <<'PY'
import json
import pathlib
import sys

release = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for asset in release.get("assets", []):
    name = asset.get("name", "")
    if name.endswith(".zip"):
        print(asset["browser_download_url"])
        break
else:
    raise SystemExit("No ZIP asset found in original port release")
PY
)"

curl -fL "$ORIGINAL_PORT_URL" -o original-port.zip
mkdir -p original-port
unzip -q original-port.zip -d original-port

ORIGINAL_MODULE="$(find original-port -type f -name cdc-acm.ko ! -name '._*' -print -quit)"
ORIGINAL_CONFIG="$(find original-port -type f -name config.ini ! -name '._*' -print -quit)"
test -n "$ORIGINAL_MODULE"
test -n "$ORIGINAL_CONFIG"

PACKAGE_NAME="m8c-223-fb-test-${M8C_VERSION}-r${PACKAGE_REVISION}"
PACKAGE_DIR="$OUT_DIR/$PACKAGE_NAME"
PORTS_DIR="$PACKAGE_DIR/roms/ports"
APP_DIR="$PORTS_DIR/m8c-223-fb-test"
mkdir -p "$APP_DIR/lib" "$APP_DIR/m8c"

cp "$BUILD_DIR/m8c/m8c" "$APP_DIR/m8c-bin"
cp -L "$SDL_LIBRARY" "$APP_DIR/lib/libSDL3.so.0"
cp "$ORIGINAL_MODULE" "$APP_DIR/cdc-acm.ko"
cp "$ORIGINAL_CONFIG" "$APP_DIR/m8c/config.ini"
cp "$BUILD_DIR/m8c/gamecontrollerdb.txt" "$APP_DIR/m8c/gamecontrollerdb.txt"
cp "$BUILD_DIR/m8c/LICENSE" "$APP_DIR/LICENSE-m8c"
cp "$BUILD_DIR/SDL3-${SDL_VERSION}/LICENSE.txt" "$APP_DIR/LICENSE-SDL.txt"

cat > "$PORTS_DIR/m8c-223-fb-test.sh" <<'SH'
#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
    controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
    controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
    controlfolder="$XDG_DATA_HOME/PortMaster"
else
    controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/m8c-223-fb-test"
BINARY="m8c-bin"
CUR_TTY="/dev/tty0"

export XDG_CONFIG_HOME="$GAMEDIR"
export XDG_DATA_HOME="$GAMEDIR"
export SDL_VIDEODRIVER="offscreen"
export SDL_VIDEO_DRIVER="offscreen"
export SDL_RENDER_DRIVER="software"
export SDL_RENDER_VSYNC="0"
export LD_LIBRARY_PATH="$GAMEDIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

mkdir -p "$GAMEDIR/m8c"
: > "$GAMEDIR/log.txt"
exec > >(tee "$GAMEDIR/log.txt") 2>&1
cd "$GAMEDIR" || exit 1

{
    echo "timestamp=$(date -Iseconds)"
    echo "launcher=/$directory/ports/m8c-223-fb-test.sh"
    echo "gamedir=$GAMEDIR"
    echo "binary=$GAMEDIR/$BINARY"
    echo "SDL_VIDEODRIVER=$SDL_VIDEODRIVER"
    echo "SDL_RENDER_DRIVER=$SDL_RENDER_DRIVER"
    echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    echo
    sha256sum "$GAMEDIR/$BINARY" "$GAMEDIR/lib/libSDL3.so.0"
    echo
    ldd "$GAMEDIR/$BINARY" || true
} > "$GAMEDIR/launcher-proof.txt" 2>&1

if ! grep -q '^cdc_acm ' /proc/modules 2>/dev/null; then
    insmod "$GAMEDIR/cdc-acm.ko" 2>/dev/null || true
fi

chmod 666 /dev/ttyACM* 2>/dev/null || true
chmod 666 /dev/fb0 2>/dev/null || true
chmod 666 "$CUR_TTY" 2>/dev/null || true

printf '\033c' > "$CUR_TTY" 2>/dev/null || true
"./$BINARY"
RESULT=$?

sync
printf '\033c' > "$CUR_TTY" 2>/dev/null || true
type pm_finish >/dev/null 2>&1 && pm_finish
exit "$RESULT"
SH

cat > "$APP_DIR/VERSIONS.txt" <<EOF
m8c=${M8C_VERSION}
SDL3=${SDL_VERSION}
package_revision=${PACKAGE_REVISION}
video_driver=offscreen
output_bridge=linux-fbdev
framebuffer=/dev/fb0
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
grep -a -q 'fbdev bridge' "$APP_DIR/m8c-bin"
bash -n "$PORTS_DIR/m8c-223-fb-test.sh"

cd "$OUT_DIR"
zip -r "${PACKAGE_NAME}.zip" "$PACKAGE_NAME"
sha256sum "${PACKAGE_NAME}.zip" > "${PACKAGE_NAME}.zip.sha256"
printf '%s\n' "$PACKAGE_NAME" > package-name.txt
