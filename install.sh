#!/bin/sh
set -eu

REPO="myldy20/m8c-trimui-brick-knulli"
BASE_URL="https://github.com/$REPO/releases/latest/download"
ARCHIVE_NAME="m8c-trimui-brick-knulli.zip"
CHECKSUM_NAME="$ARCHIVE_NAME.sha256"
WORK="/userdata/system/m8c-installer.$$"

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM HUP

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

download() {
    url="$1"
    output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 20 -o "$output" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$output" "$url"
    else
        fail "curl or wget is required"
    fi
}

ask() {
    prompt="$1"
    default="$2"
    answer=""
    if [ -r /dev/tty ]; then
        printf '%s [%s]: ' "$prompt" "$default" >/dev/tty
        IFS= read -r answer </dev/tty || true
    fi
    [ -n "$answer" ] || answer="$default"
    printf '%s' "$answer"
}

current_cpu="1008"
current_layout="face"
for settings in \
    /userdata/roms/ports/m8c-223/brick.conf \
    /userdata/roms/ports/m8c-223-fb-test/brick.conf
do
    [ -f "$settings" ] || continue
    CPU_LIMIT_MHZ="1008"
    CONTROL_PROFILE="face"
    . "$settings"
    current_cpu="$CPU_LIMIT_MHZ"
    current_layout="$CONTROL_PROFILE"
    break
done

if grep -Fq '# BEGIN m8c-trimui-brick autosave' /usr/bin/knulli-suspend 2>/dev/null; then
    current_autosave="yes"
else
    current_autosave="no"
fi

CPU="${M8C_CPU_LIMIT:-ask}"
LAYOUT="${M8C_LAYOUT:-ask}"
AUTOSAVE="${M8C_AUTOSAVE:-ask}"

if [ "$CPU" = "ask" ]; then
    echo "CPU limit while m8c is open: system, 816, 1008, 1200 or 1416 MHz."
    CPU="$(ask "CPU limit" "$current_cpu")"
fi
if [ "$LAYOUT" = "ask" ]; then
    echo "Control layout: face or classic."
    echo "  face:    A=Play B=Shift X=Edit Y=Option, Select+B exits"
    echo "  classic: A=Option B=Edit Select=Shift Start=Play, Select+Y exits"
    LAYOUT="$(ask "Control layout" "$current_layout")"
fi
if [ "$AUTOSAVE" = "ask" ]; then
    echo "Suspend autosave closes m8c one second before Knulli cuts USB power."
    AUTOSAVE="$(ask "Enable suspend autosave (yes/no)" "$current_autosave")"
fi

case "$CPU" in system|816|1008|1200|1416|keep) ;; *) fail "Invalid M8C_CPU_LIMIT: $CPU" ;; esac
case "$LAYOUT" in face|classic|keep) ;; *) fail "Invalid M8C_LAYOUT: $LAYOUT" ;; esac
case "$AUTOSAVE" in yes|no|keep) ;; *) fail "Invalid M8C_AUTOSAVE: $AUTOSAVE" ;; esac

[ "$(uname -m)" = "aarch64" ] || fail "This installer is for ARM64 TrimUI Brick"
command -v unzip >/dev/null 2>&1 || fail "unzip is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

cd /
mkdir -p "$WORK/unpacked"

echo "Downloading the latest m8c TrimUI Brick release..."
download "$BASE_URL/$ARCHIVE_NAME" "$WORK/$ARCHIVE_NAME"
download "$BASE_URL/$CHECKSUM_NAME" "$WORK/$CHECKSUM_NAME"

EXPECTED="$(awk 'NR==1 {print $1}' "$WORK/$CHECKSUM_NAME")"
ACTUAL="$(sha256sum "$WORK/$ARCHIVE_NAME" | awk '{print $1}')"

echo "Expected SHA-256: $EXPECTED"
echo "Actual SHA-256:   $ACTUAL"
[ "$EXPECTED" = "$ACTUAL" ] || fail "Release checksum mismatch"

unzip -q "$WORK/$ARCHIVE_NAME" -d "$WORK/unpacked"
PACKAGE_INSTALLER="$(find "$WORK/unpacked" -type f -name install-package.sh -print -quit)"
[ -n "$PACKAGE_INSTALLER" ] || fail "install-package.sh is missing from the release"
chmod 755 "$PACKAGE_INSTALLER"

"$PACKAGE_INSTALLER" \
    --cpu "$CPU" \
    --layout "$LAYOUT" \
    --autosave "$AUTOSAVE"

echo
echo "Done. Refresh Ports or reboot the Brick."
