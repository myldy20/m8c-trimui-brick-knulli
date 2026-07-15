#!/usr/bin/env bash
set -Eeuo pipefail

# Build the final upstream m8c revision before the SDL3 migration. The binary is
# linked against the stable SDL2 ABI, but SDL2 itself is deliberately NOT
# bundled. On the TrimUI Brick it must load Knulli's patched system SDL2, which
# contains the PowerVR/fbdev video integration used by the known-good port.
M8C_COMMIT="${M8C_COMMIT:-7b23dd89240537429a73d7c8a9cc866abf74838e}"
SDL2_BUILD_HEADERS="${SDL2_BUILD_HEADERS:-debian-bullseye}"
ORIGINAL_PORT_TAG="${ORIGINAL_PORT_TAG:-v0.1}"
PACKAGE_REVISION="${PACKAGE_REVISION:-1}"
PORT_NAME="${PORT_NAME:-m8c-sdl2-test}"
OUT_DIR="${OUT_DIR:-/work/dist-sdl2}"
BUILD_DIR="${BUILD_DIR:-/tmp/m8c-sdl2-build}"

on_error() {
    local rc=$?
    mkdir -p "$OUT_DIR"
    {
        echo "Build failed"
        echo "exit_code=$rc"
        echo "line=${BASH_LINENO[0]:-unknown}"
        echo "command=${BASH_COMMAND:-unknown}"
        echo "m8c_commit=$M8C_COMMIT"
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
    python3 \
    libsdl2-dev \
    libserialport-dev \
    patchelf \
    unzip \
    zip
rm -rf /var/lib/apt/lists/*

rm -rf "$BUILD_DIR" "$OUT_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"
cd "$BUILD_DIR"

git clone https://github.com/laamaa/m8c.git m8c
git -C m8c checkout --detach "$M8C_COMMIT"

cd "$BUILD_DIR/m8c"
make clean || true
make -j"$(nproc)"

# Reuse only the device-specific launcher base, kernel module and default Brick
# configuration from the original known-good package. The userspace binary is
# the freshly built upstream SDL2 client.
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

SHORT_COMMIT="${M8C_COMMIT:0:12}"
PACKAGE_NAME="${PORT_NAME}-${SHORT_COMMIT}-r${PACKAGE_REVISION}"
PACKAGE_DIR="$OUT_DIR/$PACKAGE_NAME"
PORTS_DIR="$PACKAGE_DIR/roms/ports"
M8C_DIR="$PORTS_DIR/$PORT_NAME"
LAUNCHER="$PORTS_DIR/$PORT_NAME.sh"

mkdir -p "$M8C_DIR/m8c"

cp "$BUILD_DIR/m8c/m8c" "$M8C_DIR/m8c-bin"
cp "$ORIGINAL_MODULE" "$M8C_DIR/cdc-acm.ko"
cp "$ORIGINAL_CONFIG" "$M8C_DIR/m8c/config.ini"
cp "$BUILD_DIR/m8c/gamecontrollerdb.txt" "$M8C_DIR/m8c/gamecontrollerdb.txt"
cp "$BUILD_DIR/m8c/LICENSE" "$M8C_DIR/LICENSE-m8c"

# Patch the dynamically constructed path in the original launcher. This is the
# exact bug that made the previous m8c-v2 test launch /ports/m8c by mistake.
python3 - "$ORIGINAL_LAUNCHER" "$LAUNCHER" "$PORT_NAME" <<'PY'
from __future__ import annotations

import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
port_name = sys.argv[3]
text = source.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")

replacement = f'GAMEDIR="/$directory/ports/{port_name}"'
text, count = re.subn(r'^GAMEDIR=.*$', replacement, text, count=1, flags=re.MULTILINE)
if count != 1:
    raise SystemExit("Could not replace the original GAMEDIR assignment exactly once.")

patterns = [
    re.compile(r'^(?P<line>[ \t]*cd[ \t]+\$GAMEDIR[ \t]*)$', re.MULTILINE),
    re.compile(r'^(?P<line>[ \t]*cd[ \t]+"\$GAMEDIR"[ \t]*)$', re.MULTILINE),
]
match = None
for pattern in patterns:
    match = pattern.search(text)
    if match:
        break
if not match:
    raise SystemExit("Could not find cd $GAMEDIR in the original launcher.")

proof = r'''

# Prove which binary is actually launched. This file is intentionally separate
# from m8c's own log so a path mix-up cannot produce another false positive.
PROOF_LOG="$GAMEDIR/launcher-proof.txt"
{
    echo "timestamp=$(date -Iseconds 2>/dev/null || date)"
    echo "launcher=$0"
    echo "gamedir=$GAMEDIR"
    echo "binary=$GAMEDIR/$BINARY"
    echo "pwd=$(pwd)"
    echo "SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-<unset>}"
    echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-<unset>}"
    echo
    echo "=== SHA256 ==="
    sha256sum "$GAMEDIR/$BINARY" 2>&1 || true
    echo
    echo "=== FILE ==="
    file "$GAMEDIR/$BINARY" 2>&1 || true
    echo
    echo "=== LDD ==="
    ldd "$GAMEDIR/$BINARY" 2>&1 || true
    echo
    echo "=== SDL2 RUNTIME ==="
    ls -l /usr/lib/libSDL2-2.0.so.0* 2>&1 || true
} > "$PROOF_LOG" 2>&1
'''

insert_at = match.end()
text = text[:insert_at] + proof + text[insert_at:]

if f'/ports/{port_name}' not in text or "launcher-proof.txt" not in text:
    raise SystemExit("Launcher validation failed.")

destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(text.rstrip() + "\n", encoding="utf-8")
PY

chmod 755 "$M8C_DIR/m8c-bin" "$LAUNCHER"
patchelf --remove-rpath "$M8C_DIR/m8c-bin" 2>/dev/null || true
strip --strip-unneeded "$M8C_DIR/m8c-bin"

cat > "$M8C_DIR/BUILD-INFO.txt" <<EOF_INFO
purpose=non-destructive SDL2 runtime baseline
port_name=$PORT_NAME
m8c_commit=$M8C_COMMIT
m8c_commit_short=$SHORT_COMMIT
sdl_build_headers=$SDL2_BUILD_HEADERS
sdl_runtime=Knulli system libSDL2-2.0.so.0 (not bundled)
original_port=$ORIGINAL_PORT_TAG
package_revision=$PACKAGE_REVISION
architecture=aarch64
build_userspace=debian-bullseye
EOF_INFO

(
    cd "$M8C_DIR"
    sha256sum m8c-bin cdc-acm.ko m8c/config.ini > SHA256SUMS
)

file "$M8C_DIR/m8c-bin"
readelf -h "$M8C_DIR/m8c-bin" | grep -E 'Class:|Machine:'
readelf -d "$M8C_DIR/m8c-bin" | tee "$OUT_DIR/dynamic-section.txt"

if ! readelf -d "$M8C_DIR/m8c-bin" | grep -q 'libSDL2-2.0.so.0'; then
    echo "ERROR: experimental binary does not depend on SDL2." >&2
    exit 1
fi

if readelf -d "$M8C_DIR/m8c-bin" | grep -q 'libSDL3'; then
    echo "ERROR: experimental binary unexpectedly depends on SDL3." >&2
    exit 1
fi

if readelf -d "$M8C_DIR/m8c-bin" | grep -Eiq 'RPATH|RUNPATH'; then
    echo "ERROR: experimental binary contains an RPATH/RUNPATH." >&2
    exit 1
fi

ldd "$M8C_DIR/m8c-bin"
bash -n "$LAUNCHER"

grep -n '^GAMEDIR=' "$LAUNCHER"
grep -n 'launcher-proof.txt' "$LAUNCHER"

cd "$OUT_DIR"
zip -r "${PACKAGE_NAME}.zip" "$PACKAGE_NAME"
sha256sum "${PACKAGE_NAME}.zip" > "${PACKAGE_NAME}.zip.sha256"
printf '%s\n' "$PACKAGE_NAME" > package-name.txt
rm -f failure.txt
