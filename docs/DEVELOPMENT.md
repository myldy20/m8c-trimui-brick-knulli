# Development notes

The production port was reached through hardware testing on a TrimUI Brick running Knulli Scarab `2026/05/11`.

- A generic SDL3 build failed with `No available video device`: the Brick has no usable generic DRM/KMS path, while Knulli's system SDL2 has a vendor PowerVR backend.
- An SDL2 baseline proved that the original port was using that vendor backend correctly.
- SDL3 offscreen rendering plus framebuffer copy produced the first working m8c 2.2.3 display.
- Clearing the framebuffer before every copy caused visible black flashes.
- Rendering directly into the live framebuffer exposed partially drawn frames and caused severe flicker.
- The accepted video path renders a completed `320x240` ARGB8888 memory surface and expands it into the active `1024x768` fbdev page.
- Callback-driven and recording-callback audio bridges produced stalls or ALSA overruns. A dedicated pump thread remained stable.
- The Brick's SDL gamepad mapping was incorrect. Raw input diagnostics established the physical map used by the release.

Historical investigation is preserved in closed PRs #1 and #2. Production source and packaging live on `main`.
