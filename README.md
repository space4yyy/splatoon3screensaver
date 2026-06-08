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
- Configurable timed cycle interval: 30, 60, 90, or 120 seconds, defaulting
  to 60 seconds.
- No sound.

## Getting Started

1. **Download & Extract**: Download the latest build from the GitHub Actions artifacts, and extract it to obtain `splatoon3-boot.saver`.
2. **Install**: Double-click `splatoon3-boot.saver` to install it. macOS will prompt you to choose:
   - **Install for this user only** (Installs to `~/Library/Screen Savers/`)
   - **Install for all users** (Installs to `/Library/Screen Savers/`, requires administrator password)

3. **Clear Quarantine Flag**: Because this screensaver is compiled outside the Mac App Store, macOS Gatekeeper may block it from running. Open your **Terminal** app and run the appropriate command below based on your installation choice:
   * **If installed for this user only**:
     ```sh
     xattr -cr ~/Library/Screen\ Savers/splatoon3-boot.saver
     ```
   * **If installed for all users**:
     ```sh
     sudo xattr -cr /Library/Screen\ Savers/splatoon3-boot.saver
     ```

4. **Select & Configure**: Open **System Settings**, navigate to **Wallpapers / Screen Savers**, select **Splatoon 3 Boot**, and click **Options** to customize colors, frame rate, and render scale.

## Log Feedback

The screensaver logs diagnostics through macOS Unified Logging.

Subsystem:

```text
ink.space4.Splatoon3Screensaver
```

When asking a user to report an issue, have them reproduce it and run:

```sh
log show --last 10m --predicate 'subsystem == "ink.space4.Splatoon3Screensaver"' --style compact --info --debug
```

For live logs during development:

```sh
log stream --predicate 'subsystem == "ink.space4.Splatoon3Screensaver"' --style compact --info --debug
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

Build a distributable `.saver` artifact locally:

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

Tag pushes build and upload the `.saver` workflow artifact through GitHub Actions:

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

- Original Shadertoy shader: `f3SGWc`, "[Splatoon 3 Boot animation](https://www.shadertoy.com/view/f3SGWc)" by [Nick27](https://www.shadertoy.com/user/Nick27)
- Splatoon is a trademark of Nintendo.
- This repository is an unofficial fan project.
