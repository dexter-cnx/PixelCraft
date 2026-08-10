# G2.4 Creative Filter GPU Preview Contract

## Status

G2.4a (`grayscale`, `invert`) has native Metal realtime preview and exact numeric parity against the Rust/photon-rs semantics.

G2.4b runtime integration is implemented for the remaining Photon preset filters using Rust-generated canonical 33³ LUTs and the already-verified Metal 3D LUT loader/sampler. Physical-device functional/parity characterization remains the verification gate before G2.4b is considered closed.

## Scope

Creative preset filters:

- `vintage`
- `oceanic`
- `lofi`
- `dramatic`
- `golden`
- `pastel_pink`

## Source of truth

Rust remains authoritative. `rust/src/bin/generate_creative_luts.rs` calls the same `photon_filters::apply` path used by committed edits/export at intensity `1.0`.

Metal contains no independently maintained preset coefficients or HSL conversion code for these filters.

## Canonical LUT

- Grid: 33 × 33 × 33
- Input domain: RGB `[0, 1]`
- Canonical cube source: `rust/creative_luts/<filter>/lut.cube`
- Runtime atlas: RGBA8
- Alpha: 255
- Sampling: same texel-center 3D LUT rule already verified by the G1 Film parity harness
- Runtime intensity: blend original color with LUT result using the same normalized `0.0 ... 1.0` intensity contract as `rust/src/photon_filters.rs`

Conceptually:

```text
source RGB
  -> canonical creative 33³ LUT (Rust-generated)
  -> effected RGB
  -> mix(source, effected, intensity)
  -> preview output
```

## Asset layout

G1 Film asset names remain unchanged. Creative assets share the existing bundle directory but use an explicit prefix so the same native loader can be reused without confusing application-level Film Profile ids with creative ids:

```text
gpu_luts/
  provia_inspired.rgba8
  velvia_inspired.rgba8
  ...
  creative_vintage.rgba8
  creative_oceanic.rgba8
  creative_lofi.rgba8
  creative_dramatic.rgba8
  creative_golden.rgba8
  creative_pastel_pink.rgba8
  manifest.json
  creative_manifest.json
```

The prefix is an internal GPU asset id only. Editor/Rust operation ids remain `vintage`, `oceanic`, etc.

## Build pipeline

`make gpu-luts` now performs:

```text
film-luts
creative-luts
  -> cargo run --bin generate_creative_luts
  -> rust/creative_luts/<filter>/lut.cube

generate_gpu_lut_atlas.py
  -> Film RGBA8 assets

generate_gpu_creative_lut_atlas.py
  -> creative_<filter>.rgba8
  -> creative_manifest.json
```

The existing iOS `Generate Film LUT Assets` build phase calls `make gpu-luts`, so Creative LUT assets are generated into the same `gpu_luts` application-resource directory without adding a second Xcode asset phase.

## Runtime rules

1. Dart sends only creative filter id + intensity.
2. Image pixels remain native.
3. `grayscale` and `invert` continue to use the exact u8 Metal compute implementation verified in G2.4a.
4. Photon preset live drafts map `filter` -> internal LUT id `creative_<filter>` and reuse `MetalFilmLutLoader` + the existing 3D LUT render path.
5. Intensity-only slider updates with the same selected preset update only LUT strength state; the LUT texture is not reloaded.
6. Selecting another tool clears the active creative GPU draft.
7. Unsupported/missing creative LUT asset -> live GPU activation fails and the Editor remains on Rust preview fallback.
8. Apply/Cancel/Undo/Redo/export remain Rust-authoritative.

## Verification gate

Before closing G2.4b:

- Rust-generated reference LUT exists for all six presets.
- Cube -> RGBA8 atlas generation passes the deterministic atlas parity rule.
- Metal 33³ sampler remains the G1-verified texel-center path.
- Device live intensity works for all six presets.
- Creative LUT interpolation vs Rust committed preview is characterized and within the accepted tolerance.
- 1024² command-completion p95 remains <= 16.67 ms on the G2 reference device.
- Visual handoff from Metal live draft to Rust committed preview has no obvious jump beyond expected LUT interpolation tolerance.

## Why LUT generation is preferred

Some Photon presets are simple per-channel operations while others chain contrast, grayscale, channel offsets, color mixing, or HSL operations. Encoding those internals independently in Metal creates a second source of truth and increases drift risk when the Rust dependency changes. Rust-generated LUTs preserve a single authoritative implementation while reusing the already-verified G1 Metal LUT sampler.
