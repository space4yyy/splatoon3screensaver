# Agent Notes

## Goal

Maintain a native macOS `.saver` recreation of Shadertoy `f3SGWc`
(`Splatoon 3 Boot animation` by Nick27).

## Current Architecture

- `Sources/Splatoon3ScreensaverView.swift`: `ScreenSaverView` wrapper. It owns
  the `CAMetalLayer`, resolves the correct screen Metal device, updates drawable
  size, and forwards `animateOneFrame()` to the renderer.
- `Sources/Renderer.swift`: Metal renderer. It builds the shader pipelines,
  owns feedback textures, steps passes A/B/C, computes the palette blend and
  bubble transforms on the CPU, and presents the final image.
- `Sources/ConfigSheetController.swift`: options sheet with the palette picker,
  cycle interval, custom inks, starting pattern, frame rate, and battery saver.
- `Sources/Settings.swift`: `ScreenSaverDefaults` storage. The module name is
  `ink.space4.Splatoon3Screensaver`.
- `Sources/PowerMonitor.swift`: battery power and Low Power Mode state for the
  battery saver frame rate cap.
- `Shaders/Splatoon3.metal`: Metal port of the Shadertoy pass graph.
- `Resources/bubble-mask.raw`: decoded 256x128 bubble mask from original
  Shadertoy `Buffer D`.

Build targets:

```sh
make
make install
make clean
```

There is no standalone preview app in the current project.

Xcode 26 and newer ship the Metal compiler separately. If `make` reports a
missing Metal Toolchain, install it with
`xcodebuild -downloadComponent MetalToolchain`.

## Development Rules

- Keep `.saver` packaging and renderer correctness separate.
- Do not reintroduce file-based diagnostics. Use Unified Logging through
  `AppLog.renderer`.
- The fluid steps on a fixed 60 Hz clock in `SplatoonSimulation.advance`, not
  in the shader. Every encoded pass A/B/C is a real step (frames 0-2
  initialise), so frame rate changes neither speed up nor slow down the ink.
- Only a starting pattern change restarts the simulation. Palette, colour, and
  frame rate changes apply to the running animation.
- Custom inks are stored as sRGB hex and linearised before the shader, because
  the image pass writes to an sRGB drawable. The built-in palettes are linear
  constants from the original shader.

## System Settings Host Behaviour

Observed on macOS 27 through `WallpaperAgent` and `legacyScreenSaver` logs:

- The preview is hosted remotely by `WallpaperAgent` (`isPreview` is false).
  The options sheet runs in a separate `legacyScreenSaver` process with a
  0x0 module view that is never started.
- Closing the sheet makes System Settings rebuild the preview. The host sends
  `startAnimation` to the outgoing view, removes that view without
  `stopAnimation`, and never starts the replacement view. The view handles this
  in `scheduleAnimationHandoff`: a replacement view starts itself shortly after
  an animating view is removed. Without it the preview stays black.
- Once the host stops displaying a layer, `nextDrawable()` blocks for its
  one-second timeout. Drawables are fetched on a background queue so the main
  thread can process the teardown. Do not use `present(afterMinimumDuration:)`;
  it waits for display feedback the remote host stops sending.
- Detached views must stop `ScreenSaverView`'s timer. Otherwise each one keeps
  waking the host about 60 times a second.
- To debug, stream `WallpaperAgent` (category `screen-saver`), `Wallpaper`
  (category `settings`), and this subsystem together.
- Avoid manually signing the outer `.saver` bundle unless crash logs
  specifically show a signing issue.
- If users report runtime problems, ask for:

```sh
log show --last 10m --predicate 'subsystem == "ink.space4.Splatoon3Screensaver"' --style compact
```

## Shader Source Facts

Observed original passes:

- `Image`
- `Buffer A`
- `Buffer B`
- `Buffer C`
- `Buffer D`

Original dependencies:

- `Buffer A` reads Buffer C.
- `Buffer B` reads Buffer A.
- `Buffer C` reads Buffer B.
- `Buffer D` reads itself.
- `Image` reads Buffer C and Buffer D.

Metal and Shadertoy have different screen/texture coordinate conventions. The
current shader intentionally flips y in offscreen simulation passes so that
feedback writes and later `texture.read()` calls address the same rows.

Port differences that keep the output identical while costing less:

- `Buffer D` is not rendered. Its palette phase is a pure function of time and
  palette mode, so `paletteBlendLocked` computes it on the CPU. The bubble mask
  is uploaded directly as a texture.
- Pass C also writes the dye channel to an `r32Float` texture, so the
  full-resolution image pass samples 4-byte texels instead of the 16-byte state.
- Bubble wobble, breathing, and scroll are evaluated in double precision on
  the CPU as affine maps of screen uv.
