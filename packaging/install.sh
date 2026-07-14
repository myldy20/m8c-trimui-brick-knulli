#!/bin/sh
set -eu

PORTS_DIR="/userdata/roms/ports"
OLD_DIR="$PORTS_DIR/m8c"
OLD_LAUNCHER="$PORTS_DIR/m8c.sh"
NEW_DIR="$PORTS_DIR/m8c-v2"
NEW_LAUNCHER="$PORTS_DIR/m8c-v2.sh"
STAGE="$PORTS_DIR/.m8c-v2-install"
PACKAGE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ "$(uname -m)" = "aarch64" ] || fail "This package is built for aarch64."
[ -f "$PACKAGE_DIR/m8c-bin" ] || fail "m8c-bin is missing from the package."
[ -f "$PACKAGE_DIR/lib/libSDL3.so.0" ] || fail "Bundled SDL3 library is missing."
[ -f "$OLD_DIR/cdc-acm.ko" ] || fail "Existing $OLD_DIR/cdc-acm.ko was not found."
[ -f "$OLD_DIR/m8c/config.ini" ] || fail "Existing m8c config was not found."
[ -f "$OLD_LAUNCHER" ] || fail "Existing $OLD_LAUNCHER was not found."

rm -rf "$STAGE"
mkdir -p "$STAGE/lib" "$STAGE/m8c"

cp "$PACKAGE_DIR/m8c-bin" "$STAGE/m8c-bin"
cp "$PACKAGE_DIR/lib/libSDL3.so.0" "$STAGE/lib/libSDL3.so.0"
cp "$OLD_DIR/cdc-acm.ko" "$STAGE/cdc-acm.ko"
cp "$OLD_DIR/m8c/config.ini" "$STAGE/m8c/config.ini"

[ ! -f "$PACKAGE_DIR/gamecontrollerdb.txt" ] || \
    cp "$PACKAGE_DIR/gamecontrollerdb.txt" "$STAGE/m8c/gamecontrollerdb.txt"
[ ! -f "$PACKAGE_DIR/VERSIONS.txt" ] || cp "$PACKAGE_DIR/VERSIONS.txt" "$STAGE/VERSIONS.txt"
[ ! -f "$PACKAGE_DIR/SHA256SUMS" ] || cp "$PACKAGE_DIR/SHA256SUMS" "$STAGE/SHA256SUMS"
[ ! -f "$PACKAGE_DIR/LICENSE-m8c" ] || cp "$PACKAGE_DIR/LICENSE-m8c" "$STAGE/LICENSE-m8c"
[ ! -f "$PACKAGE_DIR/LICENSE-SDL.txt" ] || cp "$PACKAGE_DIR/LICENSE-SDL.txt" "$STAGE/LICENSE-SDL.txt"

chmod 755 "$STAGE/m8c-bin"

TMP_LAUNCHER="$PORTS_DIR/.m8c-v2.sh.tmp"

awk '
{
    gsub("/userdata/roms/ports/m8c", "/userdata/roms/ports/m8c-v2")
    print

    if ($0 ~ /^[[:space:]]*cd[[:space:]]+\$GAMEDIR[[:space:]]*$/) {
        print "export LD_LIBRARY_PATH=\"$GAMEDIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\""
    }
}
' "$OLD_LAUNCHER" > "$TMP_LAUNCHER"

if ! grep -q 'LD_LIBRARY_PATH=.*GAMEDIR/lib' "$TMP_LAUNCHER"; then
    rm -rf "$STAGE" "$TMP_LAUNCHER"
    fail "Could not add the private SDL3 library path to the launcher."
fi

chmod 755 "$TMP_LAUNCHER"

LDD_OUTPUT="$(
    LD_LIBRARY_PATH="$STAGE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        ldd "$STAGE/m8c-bin" 2>&1 || true
)"

echo "$LDD_OUTPUT"

if echo "$LDD_OUTPUT" | grep -q 'not found'; then
    rm -rf "$STAGE" "$TMP_LAUNCHER"
    fail "One or more runtime libraries are missing. The existing m8c installation was not changed."
fi

rm -rf "$NEW_DIR"
mv "$STAGE" "$NEW_DIR"
mv "$TMP_LAUNCHER" "$NEW_LAUNCHER"

sync

echo
echo "Installed parallel m8c client:"
echo "  $NEW_DIR"
echo "  $NEW_LAUNCHER"
echo
echo "The existing installation was not modified:"
echo "  $OLD_DIR"
echo "  $OLD_LAUNCHER"
echo
echo "Refresh the Ports list or restart EmulationStation."
