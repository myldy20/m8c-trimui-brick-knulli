#!/usr/bin/env bash

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
    if asset.get("name", "").endswith(".zip"):
        print(asset["browser_download_url"])
        break
else:
    raise SystemExit("No ZIP asset found in original Brick port release")
PY
)"
curl -fL "$ORIGINAL_PORT_URL" -o original-port.zip
mkdir -p original-port
unzip -q original-port.zip -d original-port

ORIGINAL_MODULE="$(find original-port -type f -name cdc-acm.ko ! -name '._*' -print -quit)"
ORIGINAL_CONFIG="$(find original-port -type f -name config.ini ! -name '._*' -print -quit)"
test -n "$ORIGINAL_MODULE"
test -n "$ORIGINAL_CONFIG"

PACKAGE_ROOT="$OUT_DIR/m8c-trimui-brick-knulli"
PORTS_DIR="$PACKAGE_ROOT/roms/ports"
APP_DIR="$PORTS_DIR/m8c-223"
mkdir -p "$APP_DIR/lib" "$APP_DIR/m8c" "$APP_DIR/tools"

cp "$BUILD_DIR/m8c/m8c" "$APP_DIR/m8c-bin"
cp -L "$SDL_LIBRARY" "$APP_DIR/lib/libSDL3.so.0"
cp "$ORIGINAL_MODULE" "$APP_DIR/cdc-acm.ko"
cp "$ORIGINAL_CONFIG" "$APP_DIR/m8c/config.ini"
cp "$BUILD_DIR/m8c/gamecontrollerdb.txt" "$APP_DIR/m8c/gamecontrollerdb.txt"
cp "$BUILD_DIR/m8c/LICENSE" "$APP_DIR/LICENSE-m8c"
cp "$BUILD_DIR/SDL3-${SDL_VERSION}/LICENSE.txt" "$APP_DIR/LICENSE-SDL.txt"
cp /work/packaging/m8c-223.sh "$PORTS_DIR/m8c-223.sh"
cp /work/packaging/tools/configure.sh "$APP_DIR/tools/configure.sh"
cp /work/packaging/tools/suspend-autosave.sh "$APP_DIR/tools/suspend-autosave.sh"
cp /work/packaging/install-package.sh "$PACKAGE_ROOT/install-package.sh"

sed -i \
    -e 's/^idle_ms=.*/idle_ms=10/' \
    -e 's/^gamepad_analog_axis_updown=.*/gamepad_analog_axis_updown=-1/' \
    -e 's/^gamepad_analog_axis_leftright=.*/gamepad_analog_axis_leftright=-1/' \
    "$APP_DIR/m8c/config.ini"

cat > "$APP_DIR/brick.conf" <<'EOF_SETTINGS'
# m8c TrimUI Brick runtime settings
CPU_LIMIT_MHZ="1008"
CONTROL_PROFILE="face"
EOF_SETTINGS

cat > "$APP_DIR/VERSIONS.txt" <<EOF_VERSIONS
m8c=${M8C_VERSION}
SDL3=${SDL_VERSION}
release_revision=${RELEASE_REVISION}
port=m8c-223
video_driver=offscreen-software
output_bridge=linux-fbdev-completed-surface
render_resolution=320x240
render_readback=false
callback_rate_hz=120
input_mode=raw-joystick-runtime-profile
controller_guid=03006aae5e0400008e02000014010000
control_profiles=face,classic
default_profile=face
default_cpu_limit_mhz=1008
exit_face=select-plus-b
exit_classic=select-plus-y
audio_pump=dedicated-thread
audio_startup_watchdog=3x1500ms
architecture=aarch64
build_userspace=debian-bullseye
EOF_VERSIONS

chmod 755 \
    "$APP_DIR/m8c-bin" \
    "$PORTS_DIR/m8c-223.sh" \
    "$APP_DIR/tools/configure.sh" \
    "$APP_DIR/tools/suspend-autosave.sh" \
    "$PACKAGE_ROOT/install-package.sh"

patchelf --set-rpath '$ORIGIN/lib' "$APP_DIR/m8c-bin"
strip --strip-unneeded "$APP_DIR/m8c-bin"
strip --strip-unneeded "$APP_DIR/lib/libSDL3.so.0"

(
    cd "$APP_DIR"
    sha256sum m8c-bin lib/libSDL3.so.0 cdc-acm.ko m8c/config.ini > SHA256SUMS
)

LD_LIBRARY_PATH="$APP_DIR/lib" ldd "$APP_DIR/m8c-bin" | tee "$OUT_DIR/ldd.txt"
! grep -q 'not found' "$OUT_DIR/ldd.txt"
grep -a -q 'fbdev bridge: completed ARGB8888' "$APP_DIR/m8c-bin"
grep -a -q 'Brick audio startup is silent' "$APP_DIR/m8c-bin"
grep -a -q 'M8C_CONTROL_PROFILE' "$APP_DIR/m8c-bin"
bash -n "$PORTS_DIR/m8c-223.sh"
sh -n "$APP_DIR/tools/configure.sh"
sh -n "$APP_DIR/tools/suspend-autosave.sh"
sh -n "$PACKAGE_ROOT/install-package.sh"

cd "$OUT_DIR"
zip -r m8c-trimui-brick-knulli.zip m8c-trimui-brick-knulli
sha256sum m8c-trimui-brick-knulli.zip > m8c-trimui-brick-knulli.zip.sha256
