# Agent Notes

## Goal

Maintain a native macOS `.saver` recreation of Shadertoy `f3SGWc`
(`Splatoon 3 Boot animation` by Nick27).

## Current Architecture

- `Sources/Splatoon3ScreensaverView.swift`: `ScreenSaverView` wrapper. It owns
  the `CAMetalLayer`, resolves the correct screen Metal device, updates drawable
  size, and forwards `animateOneFrame()` to the renderer.
- `Sources/Renderer.swift`: Metal renderer. It builds the shader pipelines,
  owns feedback textures, renders passes A/B/C/D, and presents the final image.
- `Sources/ConfigSheetController.swift`: options sheet for FPS, render scale,
  palette mode, and custom colors.
- `Sources/Settings.swift`: `ScreenSaverDefaults` storage. The module name is
  `ink.space4.Splatoon3Screensaver`.
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

## Development Rules

- Keep `.saver` packaging and renderer correctness separate.
- Do not reintroduce file-based diagnostics. Use Unified Logging through
  `AppLog.renderer`.
- Keep render scale at or above `0.5`; the shader stores Buffer D state at
  pixel `(256, 0)`.
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
