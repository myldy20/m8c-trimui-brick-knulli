#!/bin/sh
set -eu

TARGET="/usr/bin/knulli-suspend"
BACKUP_ROOT="/userdata/system/backups/m8c"
BEGIN_MARKER="# BEGIN m8c-headless-autosave"
END_MARKER="# END m8c-headless-autosave"
ACTION="${1:-status}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -f "$TARGET" ] || fail "$TARGET was not found."
command -v python3 >/dev/null 2>&1 || fail "python3 is required."

backup_target() {
    timestamp="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
    mkdir -p "$BACKUP_ROOT"
    backup="$BACKUP_ROOT/knulli-suspend.$timestamp"
    cp "$TARGET" "$backup"
    echo "$backup"
}

install_patch() {
    if grep -Fq "$BEGIN_MARKER" "$TARGET"; then
        echo "Suspend autosave patch is already installed."
        return 0
    fi

    backup="$(backup_target)"
    tmp="/tmp/knulli-suspend.$$"

    python3 - "$TARGET" "$tmp" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
text = source.read_text(encoding="utf-8")
needle = "pm-is-supported --suspend >/dev/null 2>&1 && pm-suspend"

patch = r'''# BEGIN m8c-headless-autosave
# Give M8 Headless a moment to disconnect and autosave before Knulli removes
# power from the USB host during suspend.
if pidof m8c-bin >/dev/null 2>&1; then
    M8_TTY="$(ls /dev/ttyACM* 2>/dev/null | head -n1)"

    if [ -n "$M8_TTY" ]; then
        python3 - "$M8_TTY" <<'M8_AUTOSAVE'
import os
import sys

try:
    fd = os.open(sys.argv[1], os.O_WRONLY | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        os.write(fd, b"D")
    finally:
        os.close(fd)
except OSError:
    pass
M8_AUTOSAVE
        sleep 1
    fi
fi
# END m8c-headless-autosave

'''

if needle not in text:
    raise SystemExit("Could not find the suspend command in knulli-suspend.")

text = text.replace(needle, patch + needle, 1)
destination.write_text(text, encoding="utf-8")
PY

    chmod 755 "$tmp"
    sh -n "$tmp" || {
        rm -f "$tmp"
        fail "Patched suspend script did not pass shell syntax validation."
    }
    cp "$tmp" "$TARGET"
    rm -f "$tmp"

    echo "Suspend autosave patch installed."
    echo "Backup: $backup"
}

remove_patch() {
    if ! grep -Fq "$BEGIN_MARKER" "$TARGET"; then
        echo "Suspend autosave patch is not installed."
        return 0
    fi

    backup="$(backup_target)"
    tmp="/tmp/knulli-suspend.$$"

    python3 - "$TARGET" "$tmp" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
text = source.read_text(encoding="utf-8")
begin = "# BEGIN m8c-headless-autosave"
end = "# END m8c-headless-autosave"

start = text.find(begin)
finish = text.find(end, start)
if start < 0 or finish < 0:
    raise SystemExit("Suspend patch markers are incomplete.")

finish += len(end)
while finish < len(text) and text[finish] in "\r\n":
    finish += 1

text = text[:start] + text[finish:]
destination.write_text(text, encoding="utf-8")
PY

    chmod 755 "$tmp"
    sh -n "$tmp" || {
        rm -f "$tmp"
        fail "Restored suspend script did not pass shell syntax validation."
    }
    cp "$tmp" "$TARGET"
    rm -f "$tmp"

    echo "Suspend autosave patch removed."
    echo "Backup: $backup"
}

case "$ACTION" in
    install) install_patch ;;
    remove) remove_patch ;;
    status)
        if grep -Fq "$BEGIN_MARKER" "$TARGET"; then
            echo "Suspend autosave patch: installed"
        else
            echo "Suspend autosave patch: not installed"
        fi
        ;;
    *) fail "Usage: $0 {install|remove|status}" ;;
esac
