#!/bin/sh
set -eu

TARGET="/usr/bin/knulli-suspend"
BACKUP_DIR="/userdata/system/backups/m8c/suspend"
BEGIN_MARKER="# BEGIN m8c-trimui-brick autosave"
END_MARKER="# END m8c-trimui-brick autosave"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

is_installed() {
    [ -f "$TARGET" ] && grep -Fq "$BEGIN_MARKER" "$TARGET"
}

backup_target() {
    mkdir -p "$BACKUP_DIR"
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="$BACKUP_DIR/knulli-suspend-$stamp"
    cp "$TARGET" "$backup"
    echo "$backup"
}

install_patch() {
    [ -f "$TARGET" ] || fail "$TARGET not found"
    [ -w "$TARGET" ] || fail "$TARGET is not writable"

    if is_installed; then
        echo "Suspend autosave: enabled"
        return 0
    fi

    backup="$(backup_target)"
    tmp="/tmp/knulli-suspend.m8c.$$"
    mode="$(stat -c '%a' "$TARGET" 2>/dev/null || echo 755)"

    {
        IFS= read -r first || true
        printf '%s\n' "$first"
        cat <<'PATCH'
# BEGIN m8c-trimui-brick autosave
# Give M8 Headless time to disconnect and autosave before Knulli removes USB power.
if pidof m8c-bin >/dev/null 2>&1; then
    pkill -TERM m8c-bin 2>/dev/null || true
    sleep 1
fi
# END m8c-trimui-brick autosave
PATCH
        cat
    } < "$TARGET" > "$tmp"

    grep -Fq "$BEGIN_MARKER" "$tmp" || fail "failed to build patched suspend script"
    chmod "$mode" "$tmp"
    cp "$tmp" "$TARGET"
    rm -f "$tmp"
    sync

    echo "Suspend autosave: enabled"
    echo "Backup: $backup"
}

remove_patch() {
    [ -f "$TARGET" ] || fail "$TARGET not found"

    if ! is_installed; then
        echo "Suspend autosave: disabled"
        return 0
    fi

    backup="$(backup_target)"
    tmp="/tmp/knulli-suspend.m8c.$$"
    mode="$(stat -c '%a' "$TARGET" 2>/dev/null || echo 755)"

    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
        $0 == begin { skipping=1; next }
        $0 == end { skipping=0; next }
        !skipping { print }
    ' "$TARGET" > "$tmp"

    if grep -Fq "$BEGIN_MARKER" "$tmp"; then
        rm -f "$tmp"
        fail "failed to remove autosave block"
    fi

    chmod "$mode" "$tmp"
    cp "$tmp" "$TARGET"
    rm -f "$tmp"
    sync

    echo "Suspend autosave: disabled"
    echo "Backup: $backup"
}

case "${1:-status}" in
    install) install_patch ;;
    remove) remove_patch ;;
    status)
        if is_installed; then
            echo "Suspend autosave: enabled"
        else
            echo "Suspend autosave: disabled"
        fi
        ;;
    *)
        echo "Usage: $0 install|remove|status" >&2
        exit 2
        ;;
esac
