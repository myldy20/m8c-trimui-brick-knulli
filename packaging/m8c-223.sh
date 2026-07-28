#!/bin/bash

# This port targets Knulli on TrimUI Brick and installs into this fixed path.
# Do not depend on PortMaster's control.txt just to discover /userdata.
GAMEDIR="/userdata/roms/ports/m8c-223"
BINARY="m8c-bin"
CUR_TTY="/dev/tty0"
SETTINGS="$GAMEDIR/brick.conf"
CPU_STATE="/tmp/m8c-223-cpufreq.$$"
LOG_FILE="$GAMEDIR/log.txt"
RESULT=0

mkdir -p "$GAMEDIR" 2>/dev/null || true
if ! : > "$LOG_FILE" 2>/dev/null; then
    LOG_FILE="/tmp/m8c-223.log"
    : > "$LOG_FILE"
fi
exec > >(tee "$LOG_FILE") 2>&1

echo "m8c TrimUI Brick launcher"
echo "timestamp=$(date -Iseconds 2>/dev/null || date)"
echo "gamedir=$GAMEDIR"
echo "log=$LOG_FILE"
echo "portmaster_required=false"
echo

chmod 666 "$CUR_TTY" 2>/dev/null || true

show_error() {
    local message="$*"
    echo "ERROR: $message"
    if [ -w "$CUR_TTY" ]; then
        printf '\033c\nm8c failed to start\n\n%s\n\nLog: %s\n' "$message" "$LOG_FILE" > "$CUR_TTY" 2>/dev/null || true
        sleep 5
    fi
}

fail() {
    show_error "$*"
    exit 1
}

CPU_LIMIT_MHZ="1008"
CONTROL_PROFILE="face"
[ -f "$SETTINGS" ] && source "$SETTINGS"

case "$CPU_LIMIT_MHZ" in
    system|816|1008|1200|1416) ;;
    *) CPU_LIMIT_MHZ="1008" ;;
esac

case "$CONTROL_PROFILE" in
    face|classic) ;;
    *) CONTROL_PROFILE="face" ;;
esac

export M8C_CONTROL_PROFILE="$CONTROL_PROFILE"
export XDG_CONFIG_HOME="$GAMEDIR"
export XDG_DATA_HOME="$GAMEDIR"
export SDL_VIDEODRIVER="offscreen"
export SDL_VIDEO_DRIVER="offscreen"
export SDL_RENDER_DRIVER="software"
export SDL_RENDER_VSYNC="0"
export SDL_AUDIODRIVER="alsa"
export LD_LIBRARY_PATH="$GAMEDIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

apply_cpu_limit() {
    [ "$CPU_LIMIT_MHZ" != "system" ] || return 0

    local target=$((CPU_LIMIT_MHZ * 1000))
    local found=0
    : > "$CPU_STATE"

    for path in /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq; do
        [ -f "$path" ] || continue
        [ -w "$path" ] || continue
        local current
        current="$(cat "$path" 2>/dev/null)" || continue
        case "$current" in *[!0-9]*|'') continue ;; esac
        printf '%s=%s\n' "$path" "$current" >> "$CPU_STATE"
        if [ "$target" -lt "$current" ]; then
            printf '%s\n' "$target" > "$path" 2>/dev/null || true
        fi
        found=1
    done

    if [ "$found" -eq 0 ]; then
        for path in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
            [ -f "$path" ] || continue
            [ -w "$path" ] || continue
            local current
            current="$(cat "$path" 2>/dev/null)" || continue
            case "$current" in *[!0-9]*|'') continue ;; esac
            printf '%s=%s\n' "$path" "$current" >> "$CPU_STATE"
            if [ "$target" -lt "$current" ]; then
                printf '%s\n' "$target" > "$path" 2>/dev/null || true
            fi
        done
    fi
}

restore_cpu_limit() {
    [ -f "$CPU_STATE" ] || return 0
    while IFS='=' read -r path value; do
        [ -n "$path" ] || continue
        [ -w "$path" ] || continue
        printf '%s\n' "$value" > "$path" 2>/dev/null || true
    done < "$CPU_STATE"
    rm -f "$CPU_STATE"
}

finish() {
    restore_cpu_limit
    sync
    printf '\033c' > "$CUR_TTY" 2>/dev/null || true
}

trap finish EXIT
trap 'RESULT=130; exit "$RESULT"' INT
trap 'RESULT=143; exit "$RESULT"' TERM HUP

[ -d "$GAMEDIR" ] || fail "Installation directory is missing: $GAMEDIR"
[ -x "$GAMEDIR/$BINARY" ] || fail "Executable is missing or not executable: $GAMEDIR/$BINARY"
[ -f "$GAMEDIR/lib/libSDL3.so.0" ] || fail "Bundled SDL3 library is missing"
[ -f "$GAMEDIR/cdc-acm.ko" ] || fail "USB serial kernel module is missing"
[ -e /dev/fb0 ] || fail "Linux framebuffer /dev/fb0 is unavailable"

mkdir -p "$GAMEDIR/m8c"
cd "$GAMEDIR" || fail "Cannot enter installation directory"

{
    echo "launcher=/userdata/roms/ports/m8c-223.sh"
    echo "gamedir=$GAMEDIR"
    echo "binary=$GAMEDIR/$BINARY"
    echo "control_profile=$CONTROL_PROFILE"
    echo "cpu_limit_mhz=$CPU_LIMIT_MHZ"
    echo "portmaster_required=false"
    echo "SDL_VIDEODRIVER=$SDL_VIDEODRIVER"
    echo "SDL_RENDER_DRIVER=$SDL_RENDER_DRIVER"
    echo "SDL_AUDIODRIVER=$SDL_AUDIODRIVER"
    echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    echo
    sha256sum "$GAMEDIR/$BINARY" "$GAMEDIR/lib/libSDL3.so.0"
    echo
    ldd "$GAMEDIR/$BINARY" || true
} > "$GAMEDIR/launcher-proof.txt" 2>&1

if ! grep -q '^cdc_acm ' /proc/modules 2>/dev/null; then
    insmod "$GAMEDIR/cdc-acm.ko" 2>/dev/null || true
fi

chmod 666 /dev/ttyACM* 2>/dev/null || true
chmod 666 /dev/fb0 2>/dev/null || true

apply_cpu_limit
printf '\033c' > "$CUR_TTY" 2>/dev/null || true
"./$BINARY"
RESULT=$?

if [ "$RESULT" -ne 0 ]; then
    show_error "m8c exited with status $RESULT"
fi

exit "$RESULT"
