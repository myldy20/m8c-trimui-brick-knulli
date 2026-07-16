#!/bin/sh
set -eu

PORT_DIR="/userdata/roms/ports/m8c-223"
SETTINGS="$PORT_DIR/brick.conf"
AUTOSAVE_TOOL="$PORT_DIR/tools/suspend-autosave.sh"
CPU=""
LAYOUT=""
AUTOSAVE="keep"

usage() {
    cat <<'USAGE'
Usage:
  configure.sh status
  configure.sh [--cpu system|816|1008|1200|1416]
               [--layout face|classic]
               [--autosave yes|no|keep]

Layouts:
  face     A=Play, B=Shift, X=Edit, Y=Option, Select+B=Exit
  classic  A=Option, B=Edit, Select=Shift, Start=Play, Select+Y=Exit
USAGE
}

read_settings() {
    CPU_LIMIT_MHZ="1008"
    CONTROL_PROFILE="face"
    [ -f "$SETTINGS" ] && . "$SETTINGS"
}

write_settings() {
    mkdir -p "$PORT_DIR"
    tmp="$SETTINGS.tmp.$$"
    umask 022
    cat > "$tmp" <<EOF_SETTINGS
# m8c TrimUI Brick runtime settings
CPU_LIMIT_MHZ="$CPU_LIMIT_MHZ"
CONTROL_PROFILE="$CONTROL_PROFILE"
EOF_SETTINGS
    mv "$tmp" "$SETTINGS"
    chmod 644 "$SETTINGS"
}

status() {
    read_settings
    printf 'CPU limit: %s\n' "$CPU_LIMIT_MHZ"
    printf 'Control layout: %s\n' "$CONTROL_PROFILE"
    if [ -x "$AUTOSAVE_TOOL" ]; then
        "$AUTOSAVE_TOOL" status || true
    else
        echo "Suspend autosave: tool missing"
    fi
}

[ "${1:-}" != "status" ] || { status; exit 0; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --cpu)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            CPU="$2"; shift 2 ;;
        --layout)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            LAYOUT="$2"; shift 2 ;;
        --autosave)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            AUTOSAVE="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2 ;;
    esac
done

read_settings

if [ -n "$CPU" ]; then
    case "$CPU" in system|816|1008|1200|1416) CPU_LIMIT_MHZ="$CPU" ;; *) echo "Invalid CPU limit: $CPU" >&2; exit 2 ;; esac
fi

if [ -n "$LAYOUT" ]; then
    case "$LAYOUT" in face|classic) CONTROL_PROFILE="$LAYOUT" ;; *) echo "Invalid layout: $LAYOUT" >&2; exit 2 ;; esac
fi

write_settings

case "$AUTOSAVE" in
    yes) "$AUTOSAVE_TOOL" install ;;
    no) "$AUTOSAVE_TOOL" remove ;;
    keep) ;;
    *) echo "Invalid autosave mode: $AUTOSAVE" >&2; exit 2 ;;
esac

status
