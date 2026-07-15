#!/bin/sh
set -eu

cat >&2 <<'EOF'
The one-command installer is temporarily disabled.

The older m8c-v2.2.3-brick-r3 GitHub Release uses generic SDL3 video
backends and does not work on TrimUI Brick with Knulli Scarab.

A tested SDL3 offscreen + fbdev port is being finalized in draft PR #2:
https://github.com/myldy20/m8c-trimui-brick-knulli/pull/2

Until a new release is published, build or download the current workflow
artifact from "Build SDL3 fbdev experiment" and install it as the separate
m8c-223-fb-test Ports entry.
EOF

exit 1
