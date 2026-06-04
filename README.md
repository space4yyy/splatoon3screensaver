# Splatoon 3 Screensaver

Native macOS `.saver` recreation of the Shadertoy shader `f3SGWc`
(`Splatoon 3 Boot animation` by Nick27).

This is an unofficial fan recreation. It is not affiliated with or endorsed by
Nintendo.

## Build

Build the standalone preview app first:

```sh
make preview
open build/Splatoon3Preview.app
```

Preview shortcuts:

- `1`: solid color renderer smoke test
- `2`: UV gradient renderer smoke test
- `3`: direct bubble resource texture
- `4`: offscreen Buffer D constant write test
- `5`: offscreen Buffer D bubble-copy test
- `6`: original Buffer D feedback pass
- `7`: Buffer A only
- `8`: Buffer B after A+B
- `9`: Buffer C after A+B+C feedback
- `0`: final render
- `-`: animated bubble composite debug view after the full pass chain
- `=`: dye field debug view after the full pass chain
- `R`: reset simulation

Build the screen saver bundle:

```sh
make
```

The bundle is written to:

```text
build/Splatoon3Screensaver.saver
```

Install for the current user:

```sh
make install
```

Then open System Settings and select `Splatoon 3 Boot`.

## Features

- Native `ScreenSaverView` + `MTKView` renderer.
- Metal implementation of the multi-pass fluid simulation.
- Configurable FPS cap.
- Configurable internal render scale.
- Preset or custom warm/cool ink colors.
- No boot sound, by request.

## Shader Notes

The source Shadertoy uses five passes: `Image`, `Buffer A`, `Buffer B`,
`Buffer C`, and `Buffer D`. This port preserves the feedback pass structure and
palette state. The original `Buffer D` contains a packed 256x128 bubble bitmap;
this port decodes that bitmap into `Resources/bubble-mask.raw` and uploads it
as an exact Metal texture.
