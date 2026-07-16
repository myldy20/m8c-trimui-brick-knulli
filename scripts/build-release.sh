#!/usr/bin/env bash
set -Eeuo pipefail

export M8C_VERSION="${M8C_VERSION:-2.2.3}"
export SDL_VERSION="${SDL_VERSION:-3.2.20}"
export RELEASE_REVISION="${RELEASE_REVISION:-1}"
export ORIGINAL_PORT_TAG="${ORIGINAL_PORT_TAG:-v0.1}"
export OUT_DIR="${OUT_DIR:-/work/dist}"
export BUILD_DIR="${BUILD_DIR:-/tmp/m8c-brick-release-build}"
export PREFIX="${PREFIX:-/opt/m8c-brick-sdl3}"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl git build-essential binutils pkg-config python3-pip \
    libserialport-dev libasound2-dev libudev-dev patchelf unzip zip
rm -rf /var/lib/apt/lists/*
python3 -m pip install --no-cache-dir cmake==3.31.6 ninja==1.11.1.1

rm -rf "$BUILD_DIR" "$OUT_DIR" "$PREFIX"
mkdir -p "$BUILD_DIR" "$OUT_DIR"

source /work/scripts/build-sdl.sh
source /work/scripts/build-m8c.sh
source /work/scripts/package-release.sh
