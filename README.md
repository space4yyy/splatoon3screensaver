# Splatoon 3 Boot Screensaver

[English](README.md) | [简体中文](README.zh-CN.md)

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
- Configurable frame rate: 30, 60, 120, or Auto (the display's refresh rate).
  The ink moves at the same speed at every frame rate.
- Battery saver, on by default: runs at 30 fps on battery power or in Low
  Power Mode.
- Palette modes: random on launch, timed cycle, Splatoon 1, Splatoon 2,
  Splatoon 3, or custom warm/cool colors.
- Configurable timed cycle interval: 30, 60, 90, or 120 seconds, defaulting
  to 60 seconds.
- No sound.

## System Requirements

- macOS 13 Ventura or newer.
- A Mac with Metal support.
- Release assets are universal binaries for Apple silicon and Intel Macs,
  built by GitHub Actions. They are tested on Apple silicon only; if a release
  build does not load on your Mac, build locally from source.

## Getting Started

1. **Download & Extract**: Download `splatoon3-boot.saver.zip` from the [latest GitHub Release](https://github.com/space4yyy/splatoon3screensaver/releases/latest), then unzip it to obtain `splatoon3-boot.saver`.
2. **Clear Quarantine Flag**: This screensaver is ad-hoc signed and not notarized by Apple. macOS quarantines downloaded files, and Gatekeeper may then refuse to open it, saying Apple could not verify it is free of malware, or block it from running, leaving a black preview. Before installing, open your **Terminal** app and run this command, adjusting the path if you unzipped it elsewhere:
   ```sh
   xattr -cr ~/Downloads/splatoon3-boot.saver
   ```
   If you already installed it, run the command for where it is installed instead:
   * **If installed for this user only**:
     ```sh
     xattr -cr ~/Library/Screen\ Savers/splatoon3-boot.saver
     ```
   * **If installed for all users**:
     ```sh
     sudo xattr -cr /Library/Screen\ Savers/splatoon3-boot.saver
     ```

   Only do this for files from this project's releases; you can compare `shasum -a 256 splatoon3-boot.saver.zip` with the `sha256` digest shown next to the release asset.
3. **Install**: Double-click `splatoon3-boot.saver` to install it. macOS will prompt you to choose:
   - **Install for this user only** (Installs to `~/Library/Screen Savers/`)
   - **Install for all users** (Installs to `/Library/Screen Savers/`, requires administrator password)

4. **Select & Configure**: Open **System Settings**, navigate to **Wallpapers / Screen Savers**, select **Splatoon 3 Boot**, and click **Options** to customize ink colors, palette cycling, the starting pattern, frame rate, and the battery saver.

   On macOS 26 and later, **Options** stops responding once you close and reopen the screen saver panel in the same System Settings session. This is a System Settings bug that affects other third-party screen savers too. Quit System Settings (⌘Q), open it again, and click **Options**.

To uninstall, delete `splatoon3-boot.saver` from `~/Library/Screen Savers` (or `/Library/Screen Savers` if you installed it for all users).

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
  Xcode 26 and newer download the Metal compiler separately; if `make` reports
  a missing Metal Toolchain, run:

```sh
xcodebuild -downloadComponent MetalToolchain
```

Build only:

```sh
make
```

Build a distributable `.saver` artifact locally:

```sh
make package
```

Local builds target the architecture of the Mac running `make`. Releases build
a universal binary and stamp the bundle version:

```sh
make package ARCHS="arm64 x86_64" VERSION=1.0.6
```

Install a local build for the current user:

```sh
make install
```

Clean build artifacts:

```sh
make clean
```

GitHub Actions builds every push to `main` and every pull request, and keeps
`splatoon3-boot.saver.zip` as a workflow artifact. Tag pushes also publish it
to GitHub Releases:

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
- `Sources/PowerMonitor.swift`: battery power and Low Power Mode detection for
  the battery saver.
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
