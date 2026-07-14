#!/bin/sh
set -eu

CONFIG="/userdata/roms/ports/m8c/m8c/config.ini"
BACKUP_ROOT="/userdata/system/backups/m8c/controls"
ACTION="${1:-status}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -f "$CONFIG" ] || fail "$CONFIG was not found."
command -v python3 >/dev/null 2>&1 || fail "python3 is required."

if pidof m8c-bin >/dev/null 2>&1; then
    fail "Exit m8c before changing the control profile, otherwise it may rewrite config.ini."
fi

case "$ACTION" in
    original)
        PROFILE="original"
        SELECT_BUTTON=4
        START_BUTTON=6
        ;;
    face-buttons|face)
        PROFILE="face-buttons"
        SELECT_BUTTON=3
        START_BUTTON=2
        ;;
    status)
        python3 - "$CONFIG" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
values = {}
section = None
for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
    line = raw_line.strip()
    if not line or line.startswith((";", "#")):
        continue
    if line.startswith("[") and line.endswith("]"):
        section = line[1:-1].strip().lower()
        continue
    if section == "gamepad" and "=" in line:
        key, value = line.split("=", 1)
        values[key.strip().lower()] = value.strip()

mapping = (
    values.get("gamepad_select"),
    values.get("gamepad_start"),
    values.get("gamepad_opt"),
    values.get("gamepad_edit"),
)

if mapping == ("4", "6", "1", "0"):
    profile = "original"
elif mapping == ("3", "2", "1", "0"):
    profile = "face-buttons"
else:
    profile = "custom or unknown"

print(f"Control profile: {profile}")
print(f"  gamepad_select={mapping[0]}")
print(f"  gamepad_start={mapping[1]}")
print(f"  gamepad_opt={mapping[2]}")
print(f"  gamepad_edit={mapping[3]}")
PY
        exit 0
        ;;
    *) fail "Usage: $0 {original|face-buttons|status}" ;;
esac

mkdir -p "$BACKUP_ROOT"
timestamp="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
backup="$BACKUP_ROOT/config.ini.$timestamp"
cp "$CONFIG" "$backup"

tmp="/tmp/m8c-config.$$"
trap 'rm -f "$tmp"' EXIT INT TERM HUP

python3 - "$CONFIG" "$tmp" "$SELECT_BUTTON" "$START_BUTTON" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
select_button = sys.argv[3]
start_button = sys.argv[4]

wanted = {
    "gamepad_select": select_button,
    "gamepad_start": start_button,
    "gamepad_opt": "1",
    "gamepad_edit": "0",
}

lines = source.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
section = None
found = set()
out = []

for raw_line in lines:
    stripped = raw_line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        section = stripped[1:-1].strip().lower()
        out.append(raw_line)
        continue

    if section == "gamepad" and "=" in raw_line and not stripped.startswith((";", "#")):
        key = raw_line.split("=", 1)[0].strip().lower()
        if key in wanted:
            newline = "\r\n" if raw_line.endswith("\r\n") else "\n"
            prefix = raw_line.split("=", 1)[0]
            out.append(f"{prefix}={wanted[key]}{newline}")
            found.add(key)
            continue

    out.append(raw_line)

missing = sorted(set(wanted) - found)
if missing:
    raise SystemExit("Missing gamepad keys in config.ini: " + ", ".join(missing))

destination.write_text("".join(out), encoding="utf-8")
PY

cp "$tmp" "$CONFIG"
rm -f "$tmp"
trap - EXIT INT TERM HUP
sync

echo "Control profile applied: $PROFILE"
echo "Backup: $backup"
case "$PROFILE" in
    original)
        echo "  Select = Shift"
        echo "  Start  = Play"
        echo "  A      = Options"
        echo "  B      = Edit"
        ;;
    face-buttons)
        echo "  X      = Shift"
        echo "  Y      = Play"
        echo "  A      = Options"
        echo "  B      = Edit"
        ;;
esac
echo "  Select + Y = Exit m8c"
