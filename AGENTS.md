# Agent Notes

## Goal

Maintain a native macOS `.saver` recreation of Shadertoy `f3SGWc`
(`Splatoon 3 Boot animation` by Nick27).

## Current Architecture

- `Sources/Splatoon3ScreensaverView.swift`: `ScreenSaverView` wrapper. It owns
  the `CAMetalLayer`, resolves the correct screen Metal device, updates drawable
  size, and forwards `animateOneFrame()` to the renderer.
- `Sources/Renderer.swift`: Metal renderer. It builds the shader pipelines,
  owns feedback textures, steps passes A/B/C as compute kernels, computes the
  palette blend and bubble transforms on the CPU, and presents the final image.
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

`ARCHS` defaults to the host architecture. CI (`.github/workflows/release.yml`)
builds every push, pull request, and `v*` tag with `ARCHS="arm64 x86_64"`,
stamps `VERSION` from the tag, and publishes tag builds as a GitHub Release. It
runs on `macos-15` because Xcode 16 bundles the Metal compiler; the macOS 26
images lack the separate Metal Toolchain (actions/runner-images#13014). The
x86_64 slice is built but untested on Intel hardware.

New releases start with `.github/release-notes.md` (install steps and the
not-notarized notes), followed by GitHub's generated notes; add a What's new
section by editing the release. Keep that file and the README's Getting
Started steps in step.

Xcode 26 and newer ship the Metal compiler separately. If `make` reports a
missing Metal Toolchain, install it with
`xcodebuild -downloadComponent MetalToolchain`.

## Development Rules

- Keep `.saver` packaging and renderer correctness separate.
- Do not reintroduce file-based diagnostics. Use Unified Logging through
  `AppLog.renderer`.
- The fluid steps on a fixed 60 Hz clock in `SplatoonSimulation.advance`, not
  in the shader. Every dispatched pass A/B/C is a real step (frames 0-2
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
- Once the screen saver panel is closed and reopened in the same System
  Settings session, the host cannot show a legacy options sheet. Our sheet
  begins on the legacyScreenSaver service window, but Wallpaper never mirrors
  it (its options anchor is 97.5x16 the first time and 440x20 afterwards), and
  the unfinished request turns later Options clicks into no-ops until System
  Settings is relaunched. A fresh legacyScreenSaver process fails the same way
  (tested by killing the options process after each sheet), so the module
  cannot work around it; the README tells users to relaunch System Settings.
  WebViewScreenSaver documents the same bug. The `Options sheet requested` and
  `Options sheet ended` log lines show whether a request reached the module.
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
simulation kernels run one thread per texel and texel row 0 holds the
original's bottom row, so feedback reads and writes address the same rows and
the image pass addresses them with screen uv directly.

Port differences that keep the output identical while costing less:

- `Buffer D` is not rendered. Its palette phase is a pure function of time and
  palette mode, so `paletteBlendLocked` computes it on the CPU. The bubble mask
  is uploaded directly as a texture.
- Passes A/B/C are compute kernels in one encoder per frame. Their neighbour
  fetches land on texel centres, so they read texels directly; only pass C's
  advection interpolates.
- The image's 5-tap dye blur is bilinear between the knots of a half-texel
  lattice. `passKnots` evaluates it exactly at those 1280x721 knots after the
  last step of a frame, and the image pass samples that texture once per pixel
  instead of taking five `r32Float` samples. Pass C writes the dye to its own
  `r32Float` texture for `passKnots`.
- Bubble wobble, breathing, and scroll are evaluated in double precision on
  the CPU as affine maps of screen uv.

## Performance

Measured at 2940x1912 plus a 2560x1080 external display, 60 fps, on an M5:

- The full-resolution image pass is most of the GPU time and is now close to
  the cost of writing the drawable. Simulation steps plus knots are about a
  third. GPU power is about 0.12 W above idle (0.19 W before the knot
  lattice), and Activity Monitor shows about 12% GPU for the process.
- CPU is about 5% of one core, almost all Metal and Core Animation per-frame
  overhead (command buffer submission, the drawable's render encoder, drawable
  bookkeeping). It scales with frame rate and screen count, not shader work.
- Activity Monitor's GPU % and GPU History are busy-time figures. When
  WindowServer is already busy, for example during screen capture or remote
  desktop, they barely move when the screen saver starts; compare GPU power.
