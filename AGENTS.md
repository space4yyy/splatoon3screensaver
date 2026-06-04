# Agent Notes

## Goal

Build a native macOS screen saver for Shadertoy `f3SGWc`
(`Splatoon 3 Boot animation` by Nick27), with a normal macOS preview app used
for shader development before installing the `.saver`.

## Current Architecture

- `Shaders/Splatoon3.metal`: Metal shader library.
- `Sources/Renderer.swift`: shared `MTKView` renderer used by both the preview
  app and the screen saver.
- `PreviewApp/main.swift`: standalone debug app.
- `Sources/Splatoon3ScreensaverView.swift`: `ScreenSaverView` wrapper.
- `Resources/bubble-mask.raw`: decoded 256x128 mask from original Shadertoy
  `Buffer D`.

Build targets:

```sh
make preview
open build/Splatoon3Preview.app
make
make install
```

## Debugging Protocol

Do not debug shader correctness through System Settings first. Use the preview
app in this order:

1. `1` Solid: must be a stable solid color. If this flickers, the issue is
   MTKView/window/draw loop/metallib loading, not Shadertoy logic.
2. `2` Gradient: must be a stable UV gradient. If Solid is stable but Gradient
   flickers, inspect vertex output or drawable pipeline.
3. `3` Bubble Resource: direct draw of `Resources/bubble-mask.raw`, no
   offscreen feedback.
4. `4` Buffer D Constant: writes a fixed white 256x128 rectangle into an
   offscreen texture, then displays that area full-screen.
5. `5` Buffer D Bubble Copy: copies `Resources/bubble-mask.raw` through an
   offscreen pass, then displays that area full-screen.
6. `6` Buffer D Feedback: runs the original Buffer D feedback pass.
7. `7` Buffer A only: runs only Buffer A into an offscreen texture and displays
   dye.
8. `8` Buffer B: runs A+B and displays Buffer B dye.
9. `9` Buffer C: runs A+B+C feedback and displays Buffer C dye.
10. `0` Final: current full Shadertoy chain image pass.
11. `-` Bubble Composite: full Shadertoy chain, displaying the animated Buffer D
   bubble samples used by the final image.
12. `=` Dye Field: full Shadertoy chain, displaying Buffer C dye data.
13. `R`: recreate the renderer and reset simulation.

Only install the `.saver` after Solid/Gradient and the shader debug stages are
correct in the preview app.

## Known Issues

- The visual animation is not yet correct.
- The screen saver bundle can be killed by macOS Wallpaper settings with
  `CODESIGNING Invalid Page` if the bundle is manually ad-hoc signed. Current
  build relies on Swift/linker signing of the Mach-O and does not sign the
  outer `.saver` bundle.
- System Settings caches screen savers aggressively. Prefer the preview app.
- Previous debugging showed all debug modes flickering, so the renderer is now
  staged to isolate the issue starting from a no-texture solid color pass.
- The preview app constructs `SplatoonRenderer` with `waitForFrameCompletion:
  true`, so full-chain preview results are synchronized before swapping
  feedback textures. Keep this enabled while debugging shader correctness.

## Shadertoy Source Facts

Observed passes:

- `Image`
- `Buffer A`
- `Buffer B`
- `Buffer C`
- `Buffer D`

Original dependencies:

- `Buffer A` reads Buffer C (`4sXGR8`)
- `Buffer B` reads Buffer A (`4dXGR8`)
- `Buffer C` reads Buffer B (`XsXGR8`)
- `Buffer D` reads itself (`XdfGR8`)
- `Image` reads Buffer C and Buffer D

Original shader expects at least `640x360`; do not run the simulation buffers
below that size.

## Development Rules

- Keep `.saver` packaging separate from renderer correctness.
- Add one rendering stage at a time and verify visually before adding the next.
- Avoid changing bundle signing unless a crash report specifically says
  `CODESIGNING`.
- Do not use System Settings as the primary shader debugger.
