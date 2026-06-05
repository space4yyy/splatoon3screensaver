# Splatoon 3 Boot Screensaver

A native macOS `.saver` recreation of Nick27's Shadertoy `f3SGWc`, inspired by
the Splatoon 3 boot animation.

This is an unofficial fan recreation. It is not affiliated with, endorsed by,
or sponsored by Nintendo.

## Project Overview

The screensaver renders a multi-pass Metal fluid simulation with the same broad
pass topology as the original Shadertoy shader:

- `Buffer A/B/C`: ink dye and velocity feedback simulation.
- `Buffer D`: packed bubble mask and palette phase state.
- `Image`: final color composition.

The macOS integration uses `ScreenSaverView` backed directly by `CAMetalLayer`.
This avoids the lifecycle problems encountered with `MTKView` inside System
Settings and works more reliably across Retina displays, external monitors, and
multi-GPU setups.

Main features:

- Native Metal renderer.
- Configurable FPS cap: 30, 60, 120, or display sync.
- Configurable internal render scale: 0.5x to 1.5x.
- Palette modes: random on launch, timed cycle, Splatoon 1, Splatoon 2,
  Splatoon 3, or custom warm/cool colors.
- Bundled thumbnail images for System Settings.
- No sound.

## Getting Started

Download the latest release asset:

`Splatoon3Screensaver.saver.zip`

from:

https://github.com/space4yyy/splatoon3screensaver/releases

Unzip it, then move `Splatoon3Screensaver.saver` into:

```text
~/Library/Screen Savers/
```

If Finder does not show that folder, press `Cmd + Shift + G` and paste the path
above.

Because this is distributed outside the Mac App Store, macOS may quarantine the
downloaded bundle. If System Settings refuses to load it, run:

```sh
xattr -cr ~/Library/Screen\ Savers/Splatoon3Screensaver.saver
```

Then open System Settings and select:

`Wallpaper / Screen Savers -> Splatoon 3 Boot`

Click `Options` to configure FPS, render scale, palette mode, and custom colors.

The installed bundle should live at:

```text
~/Library/Screen Savers/Splatoon3Screensaver.saver
```

## Log Feedback

The screensaver logs diagnostics through macOS Unified Logging.

Subsystem:

```text
ink.space4.Splatoon3Screensaver
```

When asking a user to report an issue, have them reproduce it and run:

```sh
log show --last 10m --predicate 'subsystem == "ink.space4.Splatoon3Screensaver"' --style compact
```

For live logs during development:

```sh
log stream --predicate 'subsystem == "ink.space4.Splatoon3Screensaver"' --style compact
```

Users can also open Console.app and search for
`ink.space4.Splatoon3Screensaver`.

## Developer Build

Requirements:

- macOS 13 or newer.
- Full Xcode installation with `xcrun`, `metal`, and `swiftc` available.

Build only:

```sh
make
```

Build a release zip locally:

```sh
make package
```

Install a local build for the current user:

```sh
make install
```

Clean build artifacts:

```sh
make clean
```

Tag pushes build and publish the release asset through GitHub Actions:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Important files:

- `Sources/Splatoon3ScreensaverView.swift`: `ScreenSaverView` lifecycle and
  `CAMetalLayer` setup.
- `Sources/Renderer.swift`: Metal pipeline creation, feedback textures, and
  frame rendering.
- `Sources/ConfigSheetController.swift`: options sheet UI.
- `Sources/Settings.swift`: `ScreenSaverDefaults` persistence.
- `Shaders/Splatoon3.metal`: shader passes.
- `Resources/bubble-mask.raw`: decoded 256x128 bubble mask from the original
  Shadertoy `Buffer D`.
- `Resources/Info.plist`: bundle identifier and screen saver metadata.

The bundle identifier and log subsystem are:

```text
ink.space4.Splatoon3Screensaver
```

## Credits

- Original Shadertoy shader: `f3SGWc`, "Splatoon 3 Boot animation" by Nick27:
  https://www.shadertoy.com/view/f3SGWc
- Splatoon is a trademark of Nintendo.
- This repository is an unofficial fan project.
