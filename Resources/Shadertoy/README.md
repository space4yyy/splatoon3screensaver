# Shadertoy Source Provenance

Source shader: `https://www.shadertoy.com/view/f3SGWc`

Title: `Splatoon 3 Boot animation`

Author: `Nick27`

Passes observed from the logged-in Shadertoy page:

- `Image`, SHA-256 `f3f8c92568ecd2b46ad54bfe7eea7561928cdc1b52212b19be44a1202326174c`
- `Buffer A`, SHA-256 `f134028f4d241c2f4eab68435707f6acaa0df02d4b4512140717ca63b768cfe7`
- `Buffer B`, SHA-256 `8507a1857e6f3987fbc3746c2a548ce8813921adff66c06db94381467ed343cb`
- `Buffer C`, SHA-256 `d09657d4c764d7e1780ab6e1fcd932deb348585a59d25841aceada09983c9ff5`
- `Buffer D`, SHA-256 `eda8a1cf2c4d97426f096b672d9c5810d00f76069f8bdf62e9f4c79ac0a1f532`

The runtime implementation in `Shaders/Splatoon3.metal` keeps the same pass
topology. The original `Buffer D` packed bubble bitmap is decoded into
`Resources/bubble-mask.raw` and uploaded as an exact Metal texture.
