#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: patch-launcher.py INPUT OUTPUT")

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
text = source.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")

snippet = r'''

# m8c needs much less CPU than most emulators. Limit the maximum frequency
# while it is running, then restore the previous value on exit. A reboot also
# resets the kernel CPU policy if the process was interrupted unexpectedly.
CPU_LIMIT_KHZ=816000
CPU_MAX_PATH=""
for candidate in \
    /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq \
    /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
do
    if [ -r "$candidate" ] && [ -w "$candidate" ]; then
        CPU_MAX_PATH="$candidate"
        break
    fi
done

CPU_MAX_BEFORE=""
restore_cpu_max() {
    if [ -n "$CPU_MAX_PATH" ] && [ -n "$CPU_MAX_BEFORE" ]; then
        echo "$CPU_MAX_BEFORE" > "$CPU_MAX_PATH" 2>/dev/null || true
    fi
}

trap restore_cpu_max 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -n "$CPU_MAX_PATH" ]; then
    CPU_MAX_BEFORE="$(cat "$CPU_MAX_PATH" 2>/dev/null || true)"
    case "$CPU_MAX_BEFORE" in
        ''|*[!0-9]*) ;;
        *)
            if [ "$CPU_MAX_BEFORE" -gt "$CPU_LIMIT_KHZ" ]; then
                echo "$CPU_LIMIT_KHZ" > "$CPU_MAX_PATH" 2>/dev/null || true
            fi
            ;;
    esac
fi

# SDL3 is bundled with this port instead of being installed into Knulli.
export LD_LIBRARY_PATH="$GAMEDIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
'''

patterns = [
    re.compile(r"^(?P<indent>[ \t]*)cd[ \t]+\$GAMEDIR[ \t]*$", re.MULTILINE),
    re.compile(r'^(?P<indent>[ \t]*)cd[ \t]+"\$GAMEDIR"[ \t]*$', re.MULTILINE),
]

match = None
for pattern in patterns:
    match = pattern.search(text)
    if match:
        break

if not match:
    raise SystemExit("Could not find 'cd $GAMEDIR' in the original launcher.")

insert_at = match.end()
text = text[:insert_at] + snippet + text[insert_at:]

if "LD_LIBRARY_PATH" not in text or "CPU_LIMIT_KHZ=816000" not in text:
    raise SystemExit("Launcher patch validation failed.")

destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(text.rstrip() + "\n", encoding="utf-8")
