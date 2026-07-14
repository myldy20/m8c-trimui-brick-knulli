#!/usr/bin/env bash
set -Eeuo pipefail

M8C_VERSION="${M8C_VERSION:-2.2.3}"
SDL_VERSION="${SDL_VERSION:-3.2.20}"
PACKAGE_REVISION="${PACKAGE_REVISION:-2}"
ORIGINAL_PORT_TAG="${ORIGINAL_PORT_TAG:-v0.1}"
OUT_DIR="${OUT_DIR:-/work/dist}"
BUILD_DIR="${BUILD_DIR:-/tmp/m8c-build}"
PREFIX="${PREFIX:-/opt/m8c}"

on_error() {
    local rc=$?
    mkdir -p "$OUT_DIR"
    {
        echo "Build failed"
        echo "exit_code=$rc"
        echo "line=${BASH_LINENO[0]:-unknown}"
        echo "command=${BASH_COMMAND:-unknown}"
        echo "m8c=${M8C_VERSION}"
        echo "SDL3=${SDL_VERSION}"
        echo "architecture=$(uname -m)"
    } | tee "$OUT_DIR/failure.txt" >&2
    exit "$rc"
}
trap on_error ERR

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    build-essential \
    binutils \
    file \
    pkg-config \
    python3-pip \
    libserialport-dev \
    libasound2-dev \
    libdrm-dev \
    libgbm-dev \
    libegl1-mesa-dev \
    libgles2-mesa-dev \
    libudev-dev \
    patchelf \
    unzip \
    zip \
    xz-utils
rm -rf /var/lib/apt/lists/*

python3 -m pip install --no-cache-dir cmake==3.31.6 ninja==1.11.1.1

rm -rf "$BUILD_DIR" "$OUT_DIR"
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
    -DSDL_X11=OFF \
    -DSDL_WAYLAND=OFF \
    -DSDL_KMSDRM=ON \
    -DSDL_KMSDRM_SHARED=ON \
    -DSDL_OPENGL=OFF \
    -DSDL_OPENGLES=ON \
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

git clone \
    --depth 1 \
    --branch "v${M8C_VERSION}" \
    https://github.com/laamaa/m8c.git

cd "$BUILD_DIR/m8c"
make -j"$(nproc)"

# Reuse the tested Knulli launcher layout, default config and kernel module from
# the original TrimUI Brick port, then replace only the m8c userspace client.
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
    raise SystemExit("No ZIP asset found in the original port release.")
PY
)"

curl -fL "$ORIGINAL_PORT_URL" -o original-port.zip
mkdir -p original-port
unzip -q original-port.zip -d original-port

ORIGINAL_LAUNCHER="$(find original-port -type f -name m8c.sh ! -name '._*' -print -quit)"
ORIGINAL_MODULE="$(find original-port -type f -name cdc-acm.ko ! -name '._*' -print -quit)"
ORIGINAL_CONFIG="$(find original-port -type f -name config.ini ! -name '._*' -print -quit)"

test -n "$ORIGINAL_LAUNCHER"
test -n "$ORIGINAL_MODULE"
test -n "$ORIGINAL_CONFIG"

PACKAGE_NAME="m8c-trimui-brick-knulli-${M8C_VERSION}-r${PACKAGE_REVISION}"
PACKAGE_DIR="$OUT_DIR/$PACKAGE_NAME"
PORTS_DIR="$PACKAGE_DIR/roms/ports"
M8C_DIR="$PORTS_DIR/m8c"

mkdir -p "$M8C_DIR/lib" "$M8C_DIR/m8c" "$M8C_DIR/tools"

cp "$BUILD_DIR/m8c/m8c" "$M8C_DIR/m8c-bin"
cp -L "$SDL_LIBRARY" "$M8C_DIR/lib/libSDL3.so.0"
cp "$ORIGINAL_MODULE" "$M8C_DIR/cdc-acm.ko"
cp "$ORIGINAL_CONFIG" "$M8C_DIR/m8c/config.ini"
cp "$BUILD_DIR/m8c/gamecontrollerdb.txt" "$M8C_DIR/m8c/gamecontrollerdb.txt"
cp "$BUILD_DIR/m8c/LICENSE" "$M8C_DIR/LICENSE-m8c"
cp "$BUILD_DIR/SDL3-${SDL_VERSION}/LICENSE.txt" "$M8C_DIR/LICENSE-SDL.txt"
cp /work/packaging/patch-suspend.sh "$M8C_DIR/tools/patch-suspend.sh"
cp /work/packaging/install.sh "$PACKAGE_DIR/install.sh"
cp /work/README.md "$PACKAGE_DIR/README.md"

python3 /work/packaging/patch-launcher.py "$ORIGINAL_LAUNCHER" "$PORTS_DIR/m8c.sh"

chmod 755 \
    "$M8C_DIR/m8c-bin" \
    "$M8C_DIR/tools/patch-suspend.sh" \
    "$PORTS_DIR/m8c.sh" \
    "$PACKAGE_DIR/install.sh"

patchelf --set-rpath '$ORIGIN/lib' "$M8C_DIR/m8c-bin"
strip --strip-unneeded "$M8C_DIR/m8c-bin"
strip --strip-unneeded "$M8C_DIR/lib/libSDL3.so.0"

cat > "$M8C_DIR/VERSIONS.txt" <<EOF_VERSION
m8c=${M8C_VERSION}
SDL3=${SDL_VERSION}
package_revision=${PACKAGE_REVISION}
architecture=aarch64
build_userspace=debian-bullseye
original_port=${ORIGINAL_PORT_TAG}
EOF_VERSION

(
    cd "$M8C_DIR"
    sha256sum m8c-bin lib/libSDL3.so.0 cdc-acm.ko m8c/config.ini > SHA256SUMS
)

file "$M8C_DIR/m8c-bin"
readelf -h "$M8C_DIR/m8c-bin" | grep -E 'Class:|Machine:'
readelf --version-info "$M8C_DIR/m8c-bin" | grep -o 'GLIBC_[0-9.]*' | sort -Vu || true
LD_LIBRARY_PATH="$M8C_DIR/lib" ldd "$M8C_DIR/m8c-bin"
bash -n "$PORTS_DIR/m8c.sh"
sh -n "$PACKAGE_DIR/install.sh"
sh -n "$M8C_DIR/tools/patch-suspend.sh"

cd "$OUT_DIR"
zip -r "${PACKAGE_NAME}.zip" "$PACKAGE_NAME"
sha256sum "${PACKAGE_NAME}.zip" > "${PACKAGE_NAME}.zip.sha256"

printf '%s\n' "$PACKAGE_NAME" > package-name.txt
rm -f failure.txt
