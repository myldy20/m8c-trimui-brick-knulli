#!/bin/sh
set -eu

CPU="${M8C_CPU_LIMIT:-1008}"
LAYOUT="${M8C_LAYOUT:-face}"
AUTOSAVE="${M8C_AUTOSAVE:-keep}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --cpu) CPU="$2"; shift 2 ;;
        --layout) LAYOUT="$2"; shift 2 ;;
        --autosave) AUTOSAVE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

case "$CPU" in system|816|1008|1200|1416|keep) ;; *) echo "Invalid CPU limit: $CPU" >&2; exit 2 ;; esac
case "$LAYOUT" in face|classic|keep) ;; *) echo "Invalid layout: $LAYOUT" >&2; exit 2 ;; esac
case "$AUTOSAVE" in yes|no|keep) ;; *) echo "Invalid autosave mode: $AUTOSAVE" >&2; exit 2 ;; esac

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SOURCE_DIR="$PACKAGE_ROOT/roms/ports/m8c-223"
SOURCE_LAUNCHER="$PACKAGE_ROOT/roms/ports/m8c-223.sh"
PORTS="/userdata/roms/ports"
TARGET_DIR="$PORTS/m8c-223"
TARGET_LAUNCHER="$PORTS/m8c-223.sh"
LEGACY_DIR="$PORTS/m8c-223-fb-test"
LEGACY_LAUNCHER="$PORTS/m8c-223-fb-test.sh"
BACKUP_ROOT="/userdata/system/backups/m8c/releases"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_ROOT/$STAMP"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ "$(uname -m)" = "aarch64" ] || fail "This package is for ARM64 TrimUI Brick"
[ -f "$SOURCE_DIR/m8c-bin" ] || fail "Package binary is missing"
[ -f "$SOURCE_DIR/lib/libSDL3.so.0" ] || fail "Package SDL3 library is missing"
[ -f "$SOURCE_LAUNCHER" ] || fail "Package launcher is missing"

if pidof m8c-bin >/dev/null 2>&1; then
    fail "Close m8c before installing"
fi

mkdir -p "$PORTS" "$BACKUP"
PREVIOUS_DIR=""

if [ -d "$TARGET_DIR" ]; then
    mv "$TARGET_DIR" "$BACKUP/m8c-223"
    PREVIOUS_DIR="$BACKUP/m8c-223"
fi
if [ -e "$TARGET_LAUNCHER" ]; then
    mv "$TARGET_LAUNCHER" "$BACKUP/m8c-223.sh"
fi

if [ -d "$LEGACY_DIR" ]; then
    mv "$LEGACY_DIR" "$BACKUP/m8c-223-fb-test"
    [ -n "$PREVIOUS_DIR" ] || PREVIOUS_DIR="$BACKUP/m8c-223-fb-test"
fi
if [ -e "$LEGACY_LAUNCHER" ]; then
    mv "$LEGACY_LAUNCHER" "$BACKUP/m8c-223-fb-test.sh"
fi

cp -R "$SOURCE_DIR" "$TARGET_DIR"
cp "$SOURCE_LAUNCHER" "$TARGET_LAUNCHER"

if [ -n "$PREVIOUS_DIR" ] && [ -f "$PREVIOUS_DIR/m8c/config.ini" ]; then
    cp "$PREVIOUS_DIR/m8c/config.ini" "$TARGET_DIR/m8c/config.ini"
fi
if [ -n "$PREVIOUS_DIR" ] && [ -f "$PREVIOUS_DIR/brick.conf" ]; then
    cp "$PREVIOUS_DIR/brick.conf" "$TARGET_DIR/brick.conf"
fi

chmod 755 \
    "$TARGET_LAUNCHER" \
    "$TARGET_DIR/m8c-bin" \
    "$TARGET_DIR/tools/configure.sh" \
    "$TARGET_DIR/tools/suspend-autosave.sh"

if [ ! -f "$TARGET_DIR/brick.conf" ]; then
    cat > "$TARGET_DIR/brick.conf" <<'EOF_SETTINGS'
# m8c TrimUI Brick runtime settings
CPU_LIMIT_MHZ="1008"
CONTROL_PROFILE="face"
EOF_SETTINGS
fi

CONFIG_ARGS=""
[ "$CPU" = "keep" ] || CONFIG_ARGS="$CONFIG_ARGS --cpu $CPU"
[ "$LAYOUT" = "keep" ] || CONFIG_ARGS="$CONFIG_ARGS --layout $LAYOUT"
CONFIG_ARGS="$CONFIG_ARGS --autosave $AUTOSAVE"
# Intentional word splitting: arguments above contain only validated fixed values.
# shellcheck disable=SC2086
sh "$TARGET_DIR/tools/configure.sh" $CONFIG_ARGS

LDD_OUTPUT="$(LD_LIBRARY_PATH="$TARGET_DIR/lib" ldd "$TARGET_DIR/m8c-bin" 2>&1)"
echo "$LDD_OUTPUT"
echo "$LDD_OUTPUT" | grep -q 'libSDL3.so.0' || fail "Installed binary does not load bundled SDL3"
if echo "$LDD_OUTPUT" | grep -q 'not found'; then
    fail "Installed binary has missing libraries"
fi

sync

echo
echo "Installed: $TARGET_DIR"
echo "Ports entry: m8c-223"
if find "$BACKUP" -mindepth 1 -maxdepth 1 | grep -q .; then
    echo "Previous installation backup: $BACKUP"
else
    rmdir "$BACKUP" 2>/dev/null || true
fi
