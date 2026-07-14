#!/usr/bin/env bash
set -Eeuo pipefail

M8C_VERSION="${M8C_VERSION:-2.2.3}"
SDL_VERSION="${SDL_VERSION:-3.2.20}"
PACKAGE_REVISION="${PACKAGE_REVISION:-1}"
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

PACKAGE_NAME="m8c-trimui-brick-knulli-${M8C_VERSION}-r${PACKAGE_REVISION}"
PACKAGE_DIR="$OUT_DIR/$PACKAGE_NAME"
mkdir -p "$PACKAGE_DIR/lib"

cp m8c "$PACKAGE_DIR/m8c-bin"
cp -L "$SDL_LIBRARY" "$PACKAGE_DIR/lib/libSDL3.so.0"
cp gamecontrollerdb.txt "$PACKAGE_DIR/gamecontrollerdb.txt"
cp LICENSE "$PACKAGE_DIR/LICENSE-m8c"
cp "$BUILD_DIR/SDL3-${SDL_VERSION}/LICENSE.txt" "$PACKAGE_DIR/LICENSE-SDL.txt"
cp /work/packaging/install.sh "$PACKAGE_DIR/install.sh"
cp /work/README.md "$PACKAGE_DIR/README.md"

chmod 755 "$PACKAGE_DIR/m8c-bin" "$PACKAGE_DIR/install.sh"
patchelf --set-rpath '$ORIGIN/lib' "$PACKAGE_DIR/m8c-bin"
strip --strip-unneeded "$PACKAGE_DIR/m8c-bin"
strip --strip-unneeded "$PACKAGE_DIR/lib/libSDL3.so.0"

cat > "$PACKAGE_DIR/VERSIONS.txt" <<EOF
m8c=${M8C_VERSION}
SDL3=${SDL_VERSION}
package_revision=${PACKAGE_REVISION}
architecture=aarch64
build_userspace=debian-bullseye
EOF

(
    cd "$PACKAGE_DIR"
    sha256sum m8c-bin lib/libSDL3.so.0 > SHA256SUMS
)

file "$PACKAGE_DIR/m8c-bin"
readelf -h "$PACKAGE_DIR/m8c-bin" | grep -E 'Class:|Machine:'
readelf --version-info "$PACKAGE_DIR/m8c-bin" | grep -o 'GLIBC_[0-9.]*' | sort -Vu || true
ldd "$PACKAGE_DIR/m8c-bin" || true

cd "$OUT_DIR"
zip -r "${PACKAGE_NAME}.zip" "$PACKAGE_NAME"
sha256sum "${PACKAGE_NAME}.zip" > "${PACKAGE_NAME}.zip.sha256"

printf '%s\n' "$PACKAGE_NAME" > package-name.txt
rm -f failure.txt
