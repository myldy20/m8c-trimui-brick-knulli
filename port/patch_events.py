#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch_events.py PATH_TO_M8C_SOURCE")

root = pathlib.Path(sys.argv[1])


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"{description}: anchor not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


events = root / "src" / "events.c"
replace_once(
    events,
    '#include "input.h"\n',
    '#include "input.h"\n#include "brick_input.h"\n',
    "include Brick input handler",
)
replace_once(
    events,
    '''  SDL_AppResult ret_val = SDL_APP_CONTINUE;

  switch (event->type) {
''',
    '''  SDL_AppResult ret_val = SDL_APP_CONTINUE;
#ifdef BRICK_RAW_CONTROLS
  if (brick_input_handle(ctx, event)) {
    return ret_val;
  }
#endif

  switch (event->type) {
''',
    "intercept Brick input events",
)

if "brick_input_handle(ctx, event)" not in events.read_text(encoding="utf-8"):
    raise SystemExit(f"validation failed: Brick input hook missing from {events}")

print("Applied TrimUI Brick raw-input event hook")
