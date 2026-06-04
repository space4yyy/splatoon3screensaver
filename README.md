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

Then open System Settings and select `Splatoon3Screensaver`.

## Distribution & Sharing

To share this screensaver with others, you can package the compiled `.saver` bundle:

1. **Locate the bundle:** Find the built screensaver at `build/Splatoon3Screensaver.saver`.
2. **Zip the bundle:** Right-click `Splatoon3Screensaver.saver` and select **Compress "Splatoon3Screensaver.saver"** to create a `.zip` file.
3. **Send it:** Share the `.zip` file with other users.

### How to Install (for other users)

Since this screensaver is ad-hoc compiled and not signed with an Apple Developer Certificate, macOS Gatekeeper may block it or it might render black/fail to load due to sandbox restrictions. Have other users follow these steps to install and whitelist it:

1. **Extract and copy:** Unzip the file and move `Splatoon3Screensaver.saver` into their user Screen Savers directory:
   `~/Library/Screen Savers/`
   *(Tip: In Finder, press `Cmd + Shift + G`, paste `~/Library/Screen Savers/`, and press Enter).*
2. **Clear Quarantine Flag:** Open the Terminal app and run the following command to remove the macOS quarantine flag:
   ```sh
   xattr -cr ~/Library/Screen\ Savers/Splatoon3Screensaver.saver
   ```
3. **Select in Settings:** Open **System Settings -> Wallpapers / Screen Savers**, locate `Splatoon3Screensaver`, select it, and click **Options** to customize colors and frame rate.

## Features

- Native `ScreenSaverView` backed directly by `CAMetalLayer` for robust, high-performance multi-monitor and multi-GPU support.
- Metal implementation of the multi-pass fluid simulation.
- Preset historical Splatoon game color palettes (Splatoon 1, Splatoon 2, Splatoon 3, Random on launch, Cycle over time, or Custom colors).
- Dynamic aspect ratio scaling and bubble rotation to keep shapes mathematically round on ultra-wide (e.g., 21:9), Retina, and vertical displays.
- Configurable FPS cap and rendering scale.
- No boot sound, by request.

## Shader Notes

The source Shadertoy uses five passes: `Image`, `Buffer A`, `Buffer B`,
`Buffer C`, and `Buffer D`. This port preserves the feedback pass structure and
palette state. The original `Buffer D` contains a packed 256x128 bubble bitmap;
this port decodes that bitmap into `Resources/bubble-mask.raw` and uploads it
as an exact Metal texture.
