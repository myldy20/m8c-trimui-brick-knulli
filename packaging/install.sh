#!/bin/sh
set -eu

PORTS_DIR="/userdata/roms/ports"
TARGET_DIR="$PORTS_DIR/m8c"
TARGET_LAUNCHER="$PORTS_DIR/m8c.sh"
STAGE="$PORTS_DIR/.m8c-install"
PACKAGE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PAYLOAD="$PACKAGE_DIR/roms/ports"
BACKUP_ROOT="/userdata/system/backups/m8c"
SLEEP_PATCH="ask"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

for arg in "$@"; do
    case "$arg" in
        --sleep-patch) SLEEP_PATCH="yes" ;;
        --no-sleep-patch) SLEEP_PATCH="no" ;;
        --help|-h)
            cat <<'HELP'
Usage: sh install.sh [--sleep-patch | --no-sleep-patch]

--sleep-patch     Patch Knulli suspend so M8 Headless gets one second to
                  disconnect and autosave before USB power is removed.
--no-sleep-patch  Install only the m8c files and launcher.
HELP
            exit 0
            ;;
        *) fail "Unknown option: $arg" ;;
    esac
done

if [ "$SLEEP_PATCH" = "ask" ]; then
    SLEEP_PATCH="no"
    if [ -r /dev/tty ]; then
        printf 'Add autosave protection before Knulli suspend? [y/N] ' >/dev/tty
        answer=""
        IFS= read -r answer </dev/tty || true
        case "$answer" in
            y|Y|yes|YES|Yes) SLEEP_PATCH="yes" ;;
        esac
    fi
fi

[ "$(uname -m)" = "aarch64" ] || fail "This package is built for aarch64."
[ -f "$PAYLOAD/m8c/m8c-bin" ] || fail "m8c-bin is missing from the package."
[ -f "$PAYLOAD/m8c/lib/libSDL3.so.0" ] || fail "Bundled SDL3 library is missing."
[ -f "$PAYLOAD/m8c/cdc-acm.ko" ] || fail "cdc-acm.ko is missing from the package."
[ -f "$PAYLOAD/m8c/m8c/config.ini" ] || fail "config.ini is missing from the package."
[ -f "$PAYLOAD/m8c.sh" ] || fail "m8c.sh is missing from the package."

rm -rf "$STAGE"
cp -R "$PAYLOAD/m8c" "$STAGE"
chmod 755 "$STAGE/m8c-bin"

# Keep an existing user configuration when upgrading. The full old install is
# backed up below before anything is replaced.
if [ -f "$TARGET_DIR/m8c/config.ini" ]; then
    cp "$TARGET_DIR/m8c/config.ini" "$STAGE/m8c/config.ini"
fi

LDD_OUTPUT="$(
    LD_LIBRARY_PATH="$STAGE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        ldd "$STAGE/m8c-bin" 2>&1 || true
)"
echo "$LDD_OUTPUT"

if echo "$LDD_OUTPUT" | grep -q 'not found'; then
    rm -rf "$STAGE"
    fail "One or more runtime libraries are missing."
fi

BACKUP_DIR=""
if [ -e "$TARGET_DIR" ] || [ -e "$TARGET_LAUNCHER" ]; then
    timestamp="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
    BACKUP_DIR="$BACKUP_ROOT/$timestamp"
    mkdir -p "$BACKUP_DIR"
    [ ! -e "$TARGET_DIR" ] || cp -R "$TARGET_DIR" "$BACKUP_DIR/m8c"
    [ ! -e "$TARGET_LAUNCHER" ] || cp "$TARGET_LAUNCHER" "$BACKUP_DIR/m8c.sh"
fi

rm -rf "$TARGET_DIR"
mv "$STAGE" "$TARGET_DIR"
cp "$PAYLOAD/m8c.sh" "$TARGET_LAUNCHER"
chmod 755 "$TARGET_LAUNCHER" "$TARGET_DIR/m8c-bin"

if [ "$SLEEP_PATCH" = "yes" ]; then
    if ! sh "$TARGET_DIR/tools/patch-suspend.sh" install; then
        echo "WARNING: m8c was installed, but the optional suspend patch failed." >&2
    fi
fi

sync

echo
echo "m8c is installed:"
echo "  $TARGET_DIR"
echo "  $TARGET_LAUNCHER"
[ -z "$BACKUP_DIR" ] || echo "Previous installation backup: $BACKUP_DIR"
echo
echo "Refresh the Ports list or restart EmulationStation."
